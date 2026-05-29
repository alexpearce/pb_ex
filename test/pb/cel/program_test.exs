defmodule PB.CEL.ProgramTest do
  use ExUnit.Case, async: true

  alias PB.CEL
  alias PB.CEL.Env
  alias PB.CEL.Program
  alias PB.CEL.Value

  test "check accepts an Env positionally" do
    env = Env.build(vars: %{"name" => :string})
    assert {:ok, _checked} = CEL.check(~s|"hello, " + name|, env)
  end

  test "eval accepts an Env positionally" do
    env = Env.build(vars: %{"name" => :string})
    assert {:ok, value} = CEL.eval(~s|"hello, " + name|, %{"name" => "world"}, env)
    assert value == Value.string("hello, world")
  end

  test "compile bundles a checked expression with its env" do
    env = Env.build(vars: %{"name" => :string})
    assert {:ok, %Program{} = program} = CEL.compile(~s|"hello, " + name|, env)
    assert {:ok, value} = Program.eval(program, %{"name" => "alice"})
    assert value == Value.string("hello, alice")
  end

  test "eval_program runs a pre-compiled program" do
    env = Env.build(vars: %{"n" => :int})
    {:ok, program} = CEL.compile("n + 1", env)
    assert CEL.eval_program!(program, %{"n" => 4}) == Value.int(5)
  end

  test "Env.empty/0 returns a default environment" do
    assert %Env{} = env = Env.empty()
    assert env.vars == %{}
    assert env.functions == []
    assert env.container == ""
    assert env.schema == nil
  end
end
