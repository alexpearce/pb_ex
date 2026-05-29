defmodule PB.Runtime.Normalizer do
  @moduledoc false

  alias PB.Error
  alias PB.Runtime.Decoder
  alias PB.Runtime.Encoder
  alias PB.Runtime.Errors

  @spec normalize(PB.schema(), PB.Schema.Compiled.message_name(), term(), keyword) ::
          {:ok, term()} | {:error, Error.t()}
  def normalize(schema, message_name, data, opts \\ []) do
    result =
      with {:ok, opts} <- normalize_opts(opts),
           {:ok, iodata} <- Encoder.encode(schema, message_name, data, opts.encode),
           binary = IO.iodata_to_binary(iodata) do
        Decoder.decode(schema, message_name, binary, opts.decode)
      end

    result
    |> normalize_operation()
    |> Errors.normalize_result(:normalize, message_name)
  end

  @spec normalize!(PB.schema(), PB.Schema.Compiled.message_name(), term(), keyword) ::
          term()
  def normalize!(schema, message_name, data, opts \\ []) do
    case normalize(schema, message_name, data, opts) do
      {:ok, value} -> value
      {:error, %{__exception__: true} = error} -> raise error
    end
  end

  defp normalize_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      unknown = Keyword.keys(opts) -- [:defaults, :message_names, :unknown_fields]
      defaults = Keyword.get(opts, :defaults, false)
      message_names = Keyword.get(opts, :message_names, nil)
      unknown_fields = Keyword.get(opts, :unknown_fields, :error)

      cond do
        unknown != [] ->
          {:error, {:unknown_options, unknown}}

        not is_boolean(defaults) ->
          {:error, {:invalid_option, :defaults, defaults}}

        message_names not in [nil, :root] ->
          {:error, {:invalid_option, :message_names, message_names}}

        unknown_fields not in [:error, :ignore] ->
          {:error, {:invalid_option, :unknown_fields, unknown_fields}}

        true ->
          {:ok,
           %{
             encode: [unknown_fields: unknown_fields],
             decode: [defaults: defaults, message_names: message_names]
           }}
      end
    else
      {:error, {:invalid_options, Errors.type_of(opts)}}
    end
  end

  defp normalize_opts(opts), do: {:error, {:invalid_options, Errors.type_of(opts)}}

  defp normalize_operation({:error, %{__exception__: true} = error}) do
    {:error, %{error | operation: :normalize}}
  end

  defp normalize_operation(result), do: result
end
