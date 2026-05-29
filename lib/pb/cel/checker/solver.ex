defmodule PB.CEL.Checker.Solver do
  @moduledoc false

  alias PB.CEL.Checker.Types

  defstruct next_var: 0, bindings: %{}

  @type t :: %__MODULE__{
          next_var: non_neg_integer,
          bindings: %{Types.var_id() => Types.t()}
        }

  @spec new() :: t
  def new, do: %__MODULE__{}

  @spec fresh(t) :: {Types.t(), t}
  def fresh(%__MODULE__{next_var: next_var} = solver) do
    {Types.var(next_var), %{solver | next_var: next_var + 1}}
  end

  @spec resolve(t, Types.t()) :: Types.t()
  def resolve(%__MODULE__{} = solver, type), do: Types.resolve(type, solver.bindings)

  @spec finalize(t, Types.t()) :: PB.CEL.Type.t()
  def finalize(%__MODULE__{} = solver, type),
    do: solver |> finalize_native(type) |> Types.to_cel()

  @spec finalize_native(t, Types.t()) :: Types.t()
  def finalize_native(%__MODULE__{} = solver, type), do: Types.finalize(type, solver.bindings)

  @spec common(t, [Types.t()]) :: {:ok, Types.t(), t}
  def common(%__MODULE__{} = solver, []), do: {:ok, Types.dyn(), solver}

  def common(%__MODULE__{} = solver, [type | rest]) do
    Enum.reduce(rest, {:ok, type, solver}, fn next, {:ok, acc, solver} ->
      {:ok, common, solver} = common_pair(solver, acc, next)
      {:ok, common, solver}
    end)
  end

  @spec assignable(t, Types.t(), Types.t()) :: {:ok, t} | :error
  def assignable(%__MODULE__{} = solver, expected, actual) do
    expected = resolve(solver, expected)
    actual = resolve(solver, actual)

    cond do
      expected == actual ->
        {:ok, solver}

      Types.dyn?(expected) or Types.dyn?(actual) ->
        {:ok, solver}

      assignable_scalar?(expected, actual) ->
        {:ok, solver}

      Types.var?(expected) or Types.var?(actual) ->
        case unify(solver, expected, actual) do
          {:ok, _type, solver} -> {:ok, solver}
          :error -> :error
        end

      actual == Types.null() and Types.nullable?(expected) ->
        {:ok, solver}

      true ->
        assignable_composite(solver, expected, actual)
    end
  end

  @spec unify(t, Types.t(), Types.t()) :: {:ok, Types.t(), t} | :error
  def unify(%__MODULE__{} = solver, left, right) do
    left = resolve(solver, left)
    right = resolve(solver, right)

    cond do
      left == right ->
        {:ok, left, solver}

      Types.var?(left) ->
        bind(solver, left, right)

      Types.var?(right) ->
        bind(solver, right, left)

      Types.dyn?(left) or Types.dyn?(right) ->
        {:ok, Types.dyn(), solver}

      true ->
        unify_composite(solver, left, right)
    end
  end

  defp common_pair(solver, left, right) do
    left = resolve(solver, left)
    right = resolve(solver, right)

    cond do
      left == right ->
        {:ok, left, solver}

      wrapper_primitive_pair?(left, right) ->
        {:ok, wrapper_common(left, right), solver}

      Types.var?(left) or Types.var?(right) ->
        unify(solver, left, right)

      Types.dyn?(left) or Types.dyn?(right) ->
        {:ok, Types.dyn(), solver}

      left == Types.null() and Types.nullable?(right) ->
        {:ok, right, solver}

      right == Types.null() and Types.nullable?(left) ->
        {:ok, left, solver}

      true ->
        case common_composite(solver, left, right) do
          {:ok, type, solver} -> {:ok, type, solver}
          :error -> {:ok, Types.dyn(), solver}
        end
    end
  end

  defp common_composite(solver, {:list, left}, {:list, right}) do
    with {:ok, elem_type, solver} <- common_pair(solver, left, right) do
      {:ok, Types.list(elem_type), solver}
    end
  end

  defp common_composite(solver, {:map, left_key, left_value}, {:map, right_key, right_value}) do
    with {:ok, key_type, solver} <- common_pair(solver, left_key, right_key),
         {:ok, value_type, solver} <- common_pair(solver, left_value, right_value) do
      {:ok, Types.map(key_type, value_type), solver}
    end
  end

  defp common_composite(solver, {:optional, left}, {:optional, right}) do
    with {:ok, value_type, solver} <- common_optional_param(solver, left, right) do
      {:ok, Types.optional(value_type), solver}
    end
  end

  defp common_composite(solver, {:abstract, name, left}, {:abstract, name, right})
       when length(left) == length(right) do
    with {:ok, params, solver} <- common_params(solver, left, right) do
      {:ok, {:abstract, name, params}, solver}
    end
  end

  defp common_composite(_solver, _left, _right), do: :error

  defp common_params(solver, left, right) do
    left
    |> Enum.zip(right)
    |> Enum.reduce_while({:ok, [], solver}, fn {left, right}, {:ok, params, solver} ->
      case common_pair(solver, left, right) do
        {:ok, param, solver} -> {:cont, {:ok, [param | params], solver}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, params, solver} -> {:ok, Enum.reverse(params), solver}
      :error -> :error
    end
  end

  defp common_optional_param(solver, left, right) do
    left = resolve(solver, left)
    right = resolve(solver, right)

    cond do
      left == Types.null() ->
        {:ok, right, solver}

      right == Types.null() ->
        {:ok, left, solver}

      true ->
        common_pair(solver, left, right)
    end
  end

  defp assignable_composite(solver, {:list, expected}, {:list, actual}) do
    assignable(solver, expected, actual)
  end

  defp assignable_composite(
         solver,
         {:map, expected_key, expected_value},
         {:map, actual_key, actual_value}
       ) do
    with {:ok, solver} <- assignable(solver, expected_key, actual_key),
         {:ok, solver} <- assignable(solver, expected_value, actual_value) do
      {:ok, solver}
    end
  end

  defp assignable_composite(solver, {:optional, expected}, {:optional, actual}) do
    assignable(solver, expected, actual)
  end

  defp assignable_composite(
         solver,
         {:abstract, name, expected},
         {:abstract, name, actual}
       )
       when length(expected) == length(actual) do
    expected
    |> Enum.zip(actual)
    |> Enum.reduce_while({:ok, solver}, fn {expected, actual}, {:ok, solver} ->
      case assignable(solver, expected, actual) do
        {:ok, solver} -> {:cont, {:ok, solver}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp assignable_composite(_solver, _expected, _actual), do: :error

  defp assignable_scalar?(expected, actual) do
    Types.primitive_kind(expected) != nil and
      Types.primitive_kind(expected) == Types.primitive_kind(actual)
  end

  defp unify_composite(solver, {:list, left}, {:list, right}) do
    with {:ok, elem_type, solver} <- unify(solver, left, right) do
      {:ok, Types.list(elem_type), solver}
    end
  end

  defp unify_composite(solver, {:map, left_key, left_value}, {:map, right_key, right_value}) do
    with {:ok, key_type, solver} <- unify(solver, left_key, right_key),
         {:ok, value_type, solver} <- unify(solver, left_value, right_value) do
      {:ok, Types.map(key_type, value_type), solver}
    end
  end

  defp unify_composite(solver, {:optional, left}, {:optional, right}) do
    with {:ok, value_type, solver} <- unify(solver, left, right) do
      {:ok, Types.optional(value_type), solver}
    end
  end

  defp unify_composite(solver, {:abstract, name, left}, {:abstract, name, right})
       when length(left) == length(right) do
    with {:ok, params, solver} <- unify_params(solver, left, right) do
      {:ok, {:abstract, name, params}, solver}
    end
  end

  defp unify_composite(_solver, _left, _right), do: :error

  defp unify_params(solver, left, right) do
    left
    |> Enum.zip(right)
    |> Enum.reduce_while({:ok, [], solver}, fn {left, right}, {:ok, params, solver} ->
      case unify(solver, left, right) do
        {:ok, param, solver} -> {:cont, {:ok, [param | params], solver}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, params, solver} -> {:ok, Enum.reverse(params), solver}
      :error -> :error
    end
  end

  defp bind(solver, {:var, id} = var, type) do
    type = resolve(solver, type)

    if occurs?(var, type, solver) do
      :error
    else
      {:ok, type, %{solver | bindings: Map.put(solver.bindings, id, type)}}
    end
  end

  defp occurs?({:var, id}, type, solver) do
    case resolve(solver, type) do
      {:var, ^id} ->
        true

      {:type, type} ->
        occurs?(Types.var(id), type, solver)

      {:list, type} ->
        occurs?(Types.var(id), type, solver)

      {:map, key_type, value_type} ->
        occurs?(Types.var(id), key_type, solver) or occurs?(Types.var(id), value_type, solver)

      {:optional, type} ->
        occurs?(Types.var(id), type, solver)

      {:abstract, _name, params} ->
        Enum.any?(params, &occurs?(Types.var(id), &1, solver))

      _type ->
        false
    end
  end

  defp wrapper_primitive_pair?(left, right) do
    (wrapper?(left) and primitive?(right, Types.primitive_kind(left))) or
      (wrapper?(right) and primitive?(left, Types.primitive_kind(right)))
  end

  defp wrapper_common({:wrapper, primitive}, _right), do: Types.wrapper(primitive)
  defp wrapper_common(_left, {:wrapper, primitive}), do: Types.wrapper(primitive)

  defp wrapper?({:wrapper, _primitive}), do: true
  defp wrapper?(_type), do: false

  defp primitive?(type, primitive),
    do: Types.primitive_kind(type) == primitive and not wrapper?(type)
end
