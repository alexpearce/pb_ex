defmodule PB.Adapter do
  @moduledoc """
  Message-level app/proto conversion spec.

  Adapters bridge the on-wire protobuf shape (a canonical map) and a
  caller-chosen application term such as a tagged tuple, struct, or scalar.
  Each adapter registers two `{module, function}` MFAs:

    * `:to_proto` — converts an application value to the protobuf-shaped map.
    * `:from_proto` — converts a decoded protobuf map back to the application
      value.

  Callbacks must return `{:ok, value} | {:error, reason}`.

      adapter =
        %PB.Adapter{
          to_proto: {MyApp.TimestampCodec, :to_proto},
          from_proto: {MyApp.TimestampCodec, :from_proto},
          type: quote(do: DateTime.t())
        }

      PB.compile(descriptor_set,
        projections: [{:"google.protobuf.Timestamp", adapter: adapter}]
      )

  The optional `:type` field carries an Elixir typespec used for
  `PB.Adapter`-aware docs; it is otherwise inert. The fully-qualified
  message name an adapter targets is supplied by the surrounding
  `:projections` entry, not by the adapter struct itself.
  """

  @enforce_keys [:to_proto, :from_proto]
  defstruct [:to_proto, :from_proto, :type]

  @type mfa_ref :: {module(), atom()}

  @type t :: %__MODULE__{
          to_proto: mfa_ref(),
          from_proto: mfa_ref(),
          type: term() | nil
        }
end
