defmodule PB.AdapterTest do
  use ExUnit.Case, async: true

  @message :"adapter_contract.Msg"

  @descriptor_set %{
    file: [
      %{
        name: "adapter_contract.proto",
        package: "adapter_contract",
        syntax: "proto3",
        message_type: [
          %{
            name: "Msg",
            field: []
          }
        ]
      }
    ]
  }

  @adapter %PB.Adapter{
    to_proto: {__MODULE__, :to_proto},
    from_proto: {__MODULE__, :from_proto}
  }

  def to_proto(value), do: {:ok, value}
  def from_proto(value), do: {:ok, value}

  test "compile accepts an adapter projection" do
    schema = PB.compile(@descriptor_set, projections: [{@message, adapter: @adapter}])

    assert schema.messages[@message].projection.adapter == @adapter
    refute Map.has_key?(schema.messages[@message], :adapter)
  end

  test "compile rejects legacy adapter shapes" do
    bare_keyword = [
      to_proto: {__MODULE__, :to_proto},
      from_proto: {__MODULE__, :from_proto}
    ]

    bare_map = %{
      to_proto: {__MODULE__, :to_proto},
      from_proto: {__MODULE__, :from_proto}
    }

    legacy_inputs = [
      {[adapters: [@adapter]], ~r/unknown PB.compile option/},
      {[representation: [messages: %{}]], ~r/unknown PB.compile option/},
      {[projections: [{@message, adapter: bare_keyword}]], ~r/must be a %PB.Adapter\{\}/},
      {[projections: [{@message, adapter: bare_map}]], ~r/must be a %PB.Adapter\{\}/},
      {[projections: [{@message, [bare_map]}]], ~r/to be a keyword list/}
    ]

    for {opts, pattern} <- legacy_inputs do
      assert_raise ArgumentError, pattern, fn ->
        PB.compile(@descriptor_set, opts)
      end
    end
  end

  test "compile rejects projection entries without a kind" do
    assert_raise ArgumentError, ~r/must set :adapter, :struct, :unwrap, or :oneofs/, fn ->
      PB.compile(@descriptor_set, projections: [{@message, []}])
    end
  end

  test "compile rejects unknown projection options" do
    assert_raise ArgumentError, ~r/unknown PB projection option/, fn ->
      PB.compile(@descriptor_set,
        projections: [{@message, [adapter: @adapter, bogus: true]}]
      )
    end
  end

  test "compile rejects combining :adapter with structural options" do
    assert_raise ArgumentError, ~r/cannot combine :adapter with/, fn ->
      PB.compile(@descriptor_set,
        projections: [{@message, [adapter: @adapter, struct: __MODULE__]}]
      )
    end
  end
end
