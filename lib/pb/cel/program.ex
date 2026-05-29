defmodule PB.CEL.Program do
  # Internal. Not part of the published API yet; may be exposed in a
  # later release. Original module doc retained below as reference.
  #
  # Pre-compiled CEL expression bundled with its checking environment.
  #
  # A `Program` is produced by `PB.CEL.compile/2` and carries both the
  # checked expression and the `PB.CEL.Env` it was checked against. Eval
  # callers pass only the runtime variable bindings — schema, function
  # registry, and container do not need to be re-passed at each call.
  #
  #     env =
  #       PB.CEL.Env.build(
  #         schema: schema,
  #         vars: [name: :string]
  #       )
  #
  #     {:ok, program} = PB.CEL.compile(~s|"hello, " + name|, env)
  #     {:ok, value}   = PB.CEL.Program.eval(program, %{"name" => "world"})
  @moduledoc false

  alias PB.CEL.Checked
  alias PB.CEL.Env
  alias PB.CEL.Error
  alias PB.CEL.Evaluator
  alias PB.CEL.Value

  @enforce_keys [:checked, :env]
  defstruct [:checked, :env]

  @type t :: %__MODULE__{checked: Checked.t(), env: Env.t()}

  @doc """
  Bundles a previously checked expression with the environment it was checked
  against, returning a `Program` ready for `eval/2`.

  Most callers should use `PB.CEL.compile/2`, which parses, checks, and
  bundles in one call. Use this constructor when you already hold a
  `PB.CEL.Checked` and the matching `PB.CEL.Env` — for example, to
  cache the check phase and re-bundle programs with different runtime
  bindings.
  """
  @spec new(Checked.t(), Env.t()) :: t
  def new(%Checked{} = checked, %Env{} = env) do
    %__MODULE__{checked: checked, env: env}
  end

  @doc """
  Evaluates a compiled program with the supplied variable bindings.
  """
  @spec eval(t, map | keyword) :: {:ok, Value.t()} | {:error, Error.t()}
  def eval(%__MODULE__{checked: checked, env: env}, values \\ %{}) do
    Evaluator.eval(checked, values, evaluator_opts(env))
  end

  @doc """
  Evaluates a compiled program, raising on errors.
  """
  @spec eval!(t, map | keyword) :: Value.t()
  def eval!(%__MODULE__{} = program, values \\ %{}) do
    case eval(program, values) do
      {:ok, value} -> value
      {:error, %Error{} = error} -> raise error
    end
  end

  defp evaluator_opts(%Env{} = env) do
    opts = [message_schema: env.message_schema, message_runtime: env.message_runtime]

    if is_nil(env.schema) do
      opts
    else
      Keyword.put(opts, :schema, env.schema)
    end
  end
end
