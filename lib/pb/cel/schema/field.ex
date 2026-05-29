defmodule PB.CEL.Schema.Field do
  @moduledoc false

  alias PB.CEL.Type
  alias PB.CEL.WellKnownTypes

  @signed_int_types [
    :TYPE_INT32,
    :TYPE_INT64,
    :TYPE_SINT32,
    :TYPE_SINT64,
    :TYPE_SFIXED32,
    :TYPE_SFIXED64
  ]

  @unsigned_int_types [:TYPE_UINT32, :TYPE_UINT64, :TYPE_FIXED32, :TYPE_FIXED64]
  @float_types [:TYPE_FLOAT, :TYPE_DOUBLE]
  @message_types [:TYPE_MESSAGE, :TYPE_GROUP]

  @type t :: map()

  defguard signed_int_type?(type) when type in @signed_int_types
  defguard unsigned_int_type?(type) when type in @unsigned_int_types
  defguard float_type?(type) when type in @float_types
  defguard message_type?(type) when type in @message_types

  @spec cel_type(PB.CEL.Message.Schema.schema(), t()) :: {:ok, Type.t()} | {:error, String.t()}
  def cel_type(schema, %{cardinality: :map, map_key: key, map_value: value}) do
    with {:ok, key_type} <- singular_cel_type(schema, key),
         {:ok, value_type} <- singular_cel_type(schema, value) do
      {:ok, Type.map(key_type, value_type)}
    end
  end

  def cel_type(schema, %{cardinality: :repeated} = field) do
    with {:ok, elem_type} <- singular_cel_type(schema, field) do
      {:ok, Type.list(elem_type)}
    end
  end

  def cel_type(schema, field), do: singular_cel_type(schema, field)

  @spec singular_cel_type(PB.CEL.Message.Schema.schema(), t()) ::
          {:ok, Type.t()} | {:error, String.t()}
  def singular_cel_type(_schema, %{type: type}) when signed_int_type?(type),
    do: {:ok, Type.int()}

  def singular_cel_type(_schema, %{type: type}) when unsigned_int_type?(type),
    do: {:ok, Type.uint()}

  def singular_cel_type(_schema, %{type: type}) when float_type?(type),
    do: {:ok, Type.double()}

  def singular_cel_type(_schema, %{type: :TYPE_BOOL}), do: {:ok, Type.bool()}
  def singular_cel_type(_schema, %{type: :TYPE_STRING}), do: {:ok, Type.string()}
  def singular_cel_type(_schema, %{type: :TYPE_BYTES}), do: {:ok, Type.bytes()}

  def singular_cel_type(_schema, %{type: :TYPE_ENUM, type_name: type_name}),
    do: {:ok, Type.message(Atom.to_string(type_name))}

  def singular_cel_type(_schema, %{type: :TYPE_ENUM}), do: {:ok, Type.int()}

  def singular_cel_type(_schema, %{type: type, type_name: type_name})
      when message_type?(type) do
    name = Atom.to_string(type_name)

    case WellKnownTypes.field_type(name) do
      {:ok, type} -> {:ok, type}
      :error -> {:ok, Type.message(name)}
    end
  end

  def singular_cel_type(_schema, %{type: type}) do
    {:error, "unsupported protobuf field type #{inspect(type)}"}
  end
end
