defmodule PB.CEL.Error do
  @moduledoc """
  Unified error raised by CEL evaluation, including protovalidate `cel` rules.

  `:phase` discriminates `:parse`, `:check`, or `:eval`. Callers `rescue
  PB.CEL.Error` once and inspect `:phase` to discriminate if needed.
  """

  defexception [:message, :phase, :offset, :location, :expr_id, :details]

  @type phase :: :parse | :check | :eval
  @type t :: %__MODULE__{
          message: String.t(),
          phase: phase,
          offset: non_neg_integer() | nil,
          location: String.t() | nil,
          expr_id: integer() | nil,
          details: map() | nil
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      message: Keyword.fetch!(opts, :message),
      phase: Keyword.fetch!(opts, :phase),
      offset: Keyword.get(opts, :offset),
      location: Keyword.get(opts, :location),
      expr_id: Keyword.get(opts, :expr_id),
      details: Keyword.get(opts, :details)
    }
  end

  @impl Exception
  def message(%__MODULE__{message: msg, offset: nil}), do: msg
  def message(%__MODULE__{message: msg, offset: offset}), do: "#{msg} at offset #{offset}"
end
