defmodule PB.Runtime.MessageView do
  @moduledoc false

  alias PB.Runtime.Codec
  alias PB.Runtime.Errors
  alias PB.Runtime.Representation

  @type proto_fields :: map()
  @type decode_acc :: PB.Runtime.Decoder.Scan.t()

  @spec to_proto_fields(
          PB.schema(),
          PB.Schema.Compiled.message_name(),
          PB.Schema.Compiled.message(),
          term(),
          [PB.Error.path_element()]
        ) ::
          {:ok, map()} | {:error, term()}
  def to_proto_fields(schema, message_name, message, data, path) do
    with {:ok, data} <- adapter_to_proto(message, message_name, data, path),
         {:ok, fields} <- Representation.to_proto(schema, message, message_name, data, path),
         :ok <- require_proto_fields(fields, path) do
      {:ok, fields}
    end
  end

  @spec from_proto_fields(
          PB.schema(),
          PB.Schema.Compiled.message(),
          proto_fields(),
          decode_acc(),
          [PB.Error.path_element()]
        ) :: {:ok, term()} | {:error, term()}
  def from_proto_fields(schema, message, fields, acc, path) do
    Representation.from_proto(fields, acc, message, schema, path)
  end

  # The adapter is one level: the engine recurses its output. An adapter-mode
  # message has no representation (mutual exclusivity), so the downstream
  # `Representation.to_proto` is a no-op.
  defp adapter_to_proto(message, message_name, data, path) do
    case message_adapter(message) do
      nil ->
        {:ok, data}

      adapter ->
        Codec.adapter_to_proto(adapter, message_name, data, path)
    end
  end

  defp message_adapter(%{projection: %{adapter: adapter}}) when not is_nil(adapter), do: adapter
  defp message_adapter(_message), do: nil

  defp require_proto_fields(fields, _path) when is_map(fields) and not is_struct(fields), do: :ok

  defp require_proto_fields(fields, path) do
    {:error, {:invalid_value, path, :map, Errors.type_of(fields)}}
  end
end
