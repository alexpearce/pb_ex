defmodule PB.DecodeError do
  @moduledoc """
  Structurally invalid serialized input: protobuf wire bytes that are truncated
  or malformed, or JSON text that is not well-formed for the target. The
  `:format` field discriminates `:wire` from `:json`. See `PB.Error`.
  """

  @typedoc "Which structural-decode failure this is."
  @type kind :: :malformed | :malformed_json | :duplicate_field

  @type t :: %__MODULE__{
          kind: kind | nil,
          format: :wire | :json | nil,
          operation: PB.Error.operation() | nil,
          message_name: atom | nil,
          path: [PB.Error.path_element()],
          reason: term,
          details: map
        }

  defexception kind: nil,
               format: nil,
               operation: nil,
               message_name: nil,
               path: [],
               reason: nil,
               details: %{}

  @impl Exception
  def message(%__MODULE__{} = error),
    do: PB.Error.context(format(error), error.operation, error.message_name)

  defp format(%__MODULE__{kind: :malformed, path: path, reason: reason}) do
    "malformed protobuf input#{PB.Error.format_location(path)}#{PB.Error.format_reason(reason)}"
  end

  defp format(%__MODULE__{kind: :duplicate_field, path: path, reason: reason}) do
    "duplicate field#{PB.Error.format_location(path)}#{PB.Error.format_reason(reason)}"
  end

  defp format(%__MODULE__{path: path, reason: reason}) do
    "malformed JSON input#{PB.Error.format_location(path)}#{PB.Error.format_reason(reason)}"
  end
end
