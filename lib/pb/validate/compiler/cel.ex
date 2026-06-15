defmodule PB.Validate.Compiler.CEL do
  @moduledoc false

  # Compiles CEL rule sources into checked `CELOp`s for `PB.Validate.Compiler`.
  # Owns parsing, type-checking against a compile-time env, rule-path assignment
  # for user `cel`/`cel_expression` rules, and the `:validate` cel-op merge helper.

  alias PB.CEL
  alias PB.CEL.Checker.Types, as: CType
  alias PB.CEL.Checked
  alias PB.CEL.Type
  alias PB.Validate.CELExtensions
  alias PB.Validate.CompileError
  alias PB.Validate.Schema, as: ValidateSchema

  @matches_eval {:mfa, {PB.CEL.Runtime.Strings, :matches}}

  @doc """
  Merges compiled CEL ops into an entry's `:validate`, leaving it untouched when
  there are none.
  """
  def add_cel_ops(entry, []), do: entry

  def add_cel_ops(entry, ops) do
    Map.update(entry, :validate, %{cel: ops}, fn validate ->
      Map.update(validate, :cel, ops, &(&1 ++ ops))
    end)
  end

  @doc """
  Compiles user `cel`/`cel_expression` rules on an entry and merges the ops in.
  """
  def add_user_cel_validation(
        entry,
        rules,
        schema,
        target,
        this_type,
        kind,
        rule_path_kind \\ nil
      )

  def add_user_cel_validation(entry, [], _schema, _target, _this_type, _kind, _rule_path_kind),
    do: entry

  def add_user_cel_validation(entry, rules, schema, target, this_type, kind, rule_path_kind) do
    rule_path_kind = rule_path_kind || kind

    add_cel_ops(
      entry,
      compile_user_cel_ops(rules, schema, target, this_type, kind, [], rule_path_kind)
    )
  end

  @doc """
  Compiles a list of user CEL rules into ops, assigning each a rule path.
  """
  def compile_user_cel_ops(
        rules,
        schema,
        target,
        this_type,
        kind,
        path_prefix,
        rule_path_kind
      ) do
    rules
    |> Enum.with_index()
    |> Enum.map(fn {rule, index} ->
      rule_path =
        case rule_path_kind do
          :message_cel ->
            ValidateSchema.message_cel_rule_path(index)

          :message_cel_expression ->
            ValidateSchema.message_cel_expression_rule_path(index)

          :field_cel ->
            ValidateSchema.field_cel_rule_path(index, path_prefix)

          :field_cel_expression ->
            ValidateSchema.field_cel_expression_rule_path(index, path_prefix)
        end

      proto_rule_path = if kind == :message_cel, do: nil, else: rule_path

      compile_cel_rule(rule, schema, target, %{"this" => this_type},
        kind: kind,
        rule_path: rule_path,
        proto_rule_path: proto_rule_path
      )
    end)
  end

  @doc """
  Parses, type-checks, and wraps a single CEL rule into a `CELOp`.
  """
  def compile_cel_rule(rule, schema, target, vars, attrs) do
    attrs = Map.new(attrs)
    id = Map.get(rule, :id) || ""
    message = Map.get(rule, :message) || ""
    source = rule_expression(rule)

    env =
      CEL.Env.build(
        schema: schema,
        message_schema: PB.Validate.CEL.MessageSchema,
        vars: Map.put_new(vars, "now", Type.timestamp()),
        functions: CELExtensions.functions()
      )

    parsed =
      case CEL.parse(source, location: target <> "#" <> id) do
        {:ok, parsed} ->
          parsed

        {:error, error} ->
          raise CompileError, target: target, constraint_id: id, stage: :parse, cause: error
      end

    checked =
      case CEL.check(parsed, env) do
        {:ok, checked} ->
          checked

        {:error, error} ->
          raise CompileError, target: target, constraint_id: id, stage: :check, cause: error
      end

    if valid_result_type?(checked.root_type) do
      regexes = compile_static_regexes!(checked, Map.get(attrs, :vars, %{}), target, id)

      ValidateSchema.cel_op(
        %{
          id: id,
          message: message,
          checked: checked,
          source: source,
          regexes: regexes
        }
        |> Map.merge(attrs)
      )
    else
      raise CompileError,
        target: target,
        constraint_id: id,
        stage: :type,
        cause:
          "CEL result type #{CType.format(checked.root_type)} is not assignable to bool or string"
    end
  end

  @doc "The constraint id of the first rule in a list, or an empty string."
  def first_rule_id([rule | _rules]), do: Map.get(rule, :id) || ""
  def first_rule_id([]), do: ""

  defp rule_expression(%{expression: expression}), do: expression || ""

  defp compile_static_regexes!(%Checked{} = checked, vars, target, id) do
    case compile_static_regexes(checked, vars) do
      {:ok, regexes} ->
        regexes

      {:error, reason} ->
        raise CompileError,
          target: target,
          constraint_id: id,
          stage: :regex,
          cause: reason
    end
  end

  defp compile_static_regexes(%Checked{ops: ops}, vars) do
    Enum.reduce_while(ops, {:ok, %{}}, fn
      {id, {:call, %{eval: @matches_eval} = op}}, {:ok, regexes} ->
        case static_match_pattern(op, ops, vars) do
          {:ok, pattern} ->
            case Regex.compile(pattern) do
              {:ok, regex} ->
                {:cont, {:ok, Map.put(regexes, id, regex)}}

              {:error, {reason, at}} ->
                {:halt, {:error, "invalid regex at #{at}: #{reason}"}}
            end

          :dynamic ->
            {:cont, {:ok, regexes}}
        end

      _op, acc ->
        {:cont, acc}
    end)
  end

  defp static_match_pattern(%{arg_ids: []}, _ops, _vars), do: :dynamic

  defp static_match_pattern(%{arg_ids: arg_ids}, ops, vars) do
    arg_ids
    |> List.last()
    |> static_string(ops, vars)
  end

  defp static_string(id, ops, vars) do
    case static_value(id, ops, vars, MapSet.new()) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _other -> :dynamic
    end
  end

  defp static_value(id, ops, vars, seen) when is_integer(id) do
    if MapSet.member?(seen, id) do
      :dynamic
    else
      seen = MapSet.put(seen, id)

      case Map.get(ops, id) do
        {:const, %{value: {:string, value}}} ->
          {:ok, value}

        {:ident, %{kind: :var, name: name}} ->
          Map.fetch(vars, name)

        {:select, %{receiver_id: receiver_id} = select} ->
          case static_value(receiver_id, ops, vars, seen) do
            {:ok, receiver} -> static_select(receiver, select)
            :dynamic -> :dynamic
            :error -> :dynamic
          end

        _other ->
          :dynamic
      end
    end
  end

  defp static_value(_id, _ops, _vars, _seen), do: :dynamic

  defp static_select(value, select) when is_map(value) and not is_struct(value) do
    select
    |> static_select_keys()
    |> Enum.find_value(:dynamic, fn key ->
      case Map.fetch(value, key) do
        {:ok, value} -> {:ok, value}
        :error -> false
      end
    end)
  end

  defp static_select(_value, _select), do: :dynamic

  defp static_select_keys(select) do
    [
      get_in(select, [:field_ref, :field]),
      Map.get(select, :field)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp valid_result_type?(type) do
    CType.assignable?(:bool, type) or CType.assignable?(:string, type)
  end
end
