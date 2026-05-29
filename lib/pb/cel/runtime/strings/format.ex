defmodule PB.CEL.Runtime.Strings.Format do
  @moduledoc false

  alias PB.CEL.Checker.Types, as: CType
  alias PB.CEL.Value
  alias PB.CEL.Runtime.Time

  @type result :: {:ok, Value.t()} | {:error, String.t()}

  @spec format([Value.t()]) :: result
  def format([{:string, pattern}, {:list, args}]), do: format(pattern, args)
  def format(_values), do: {:error, "no such overload"}

  defp format(pattern, args) do
    case format(pattern, args, 0, []) do
      {:ok, parts} -> {:ok, Value.string(parts |> Enum.reverse() |> IO.iodata_to_binary())}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format(<<"%%", rest::binary>>, args, index, parts) do
    format(rest, args, index, ["%" | parts])
  end

  defp format(<<"%", rest::binary>>, args, index, parts) do
    with {:ok, clause, rest} <- parse_clause(rest),
         {:ok, arg} <- fetch_arg(args, index),
         {:ok, rendered} <- render_clause(clause, arg) do
      format(rest, args, index + 1, [rendered | parts])
    end
  end

  defp format(<<char::utf8, rest::binary>>, args, index, parts) do
    format(rest, args, index, [<<char::utf8>> | parts])
  end

  defp format("", _args, _index, parts), do: {:ok, parts}

  defp parse_clause(<<?., rest::binary>>) do
    with {digits, <<verb, rest::binary>>} when digits != "" <- take_digits(rest, "") do
      parse_verb(verb, String.to_integer(digits), rest)
    else
      _other -> {:error, ~s(could not parse formatting clause)}
    end
  end

  defp parse_clause(<<verb, rest::binary>>), do: parse_verb(verb, nil, rest)
  defp parse_clause(""), do: {:error, ~s(could not parse formatting clause)}

  defp parse_verb(verb, precision, rest) when verb in [?s, ?d, ?b, ?o, ?x, ?X, ?f, ?e] do
    clause = %{verb: <<verb>>, precision: precision}

    if valid_precision?(clause) do
      {:ok, clause, rest}
    else
      {:error, ~s(could not parse formatting clause)}
    end
  end

  defp parse_verb(verb, _precision, _rest) do
    {:error, ~s(could not parse formatting clause: unrecognized formatting clause "#{<<verb>>}")}
  end

  defp take_digits(<<digit, rest::binary>>, acc) when digit in ?0..?9 do
    take_digits(rest, <<acc::binary, digit>>)
  end

  defp take_digits(rest, acc), do: {acc, rest}

  defp valid_precision?(%{verb: verb, precision: nil}) when verb in ["f", "e"], do: true

  defp valid_precision?(%{verb: verb, precision: precision}) when verb in ["f", "e"],
    do: precision >= 0

  defp valid_precision?(%{precision: nil}), do: true
  defp valid_precision?(_clause), do: false

  defp fetch_arg(args, index) do
    case Enum.fetch(args, index) do
      {:ok, arg} -> {:ok, arg}
      :error -> {:error, "index #{index} out of range"}
    end
  end

  defp render_clause(%{verb: "s"}, value), do: render_string(value)
  defp render_clause(%{verb: "d"}, value), do: render_decimal(value)
  defp render_clause(%{verb: "b"}, value), do: render_binary(value)
  defp render_clause(%{verb: "o"}, value), do: render_octal(value)
  defp render_clause(%{verb: "x"}, value), do: render_hex(value, :lower)
  defp render_clause(%{verb: "X"}, value), do: render_hex(value, :upper)

  defp render_clause(%{verb: "f", precision: precision}, value) do
    render_fixed(value, precision || 6)
  end

  defp render_clause(%{verb: "e", precision: precision}, value) do
    render_scientific(value, precision || 6)
  end

  defp render_string(:null), do: {:ok, "null"}
  defp render_string({:bool, value}), do: {:ok, to_string(value)}
  defp render_string({:int, value}), do: {:ok, Integer.to_string(value)}
  defp render_string({:uint, value}), do: {:ok, Integer.to_string(value)}
  defp render_string({:double, value}), do: {:ok, double_to_string(value)}
  defp render_string({:string, value}), do: {:ok, value}
  defp render_string({:timestamp, _ns} = value), do: Time.format_timestamp(value)
  defp render_string({:duration, _ns} = value), do: Time.format_duration(value)

  defp render_string({:bytes, value}) do
    if String.valid?(value), do: {:ok, value}, else: string_clause_error({:bytes, value})
  end

  defp render_string({:list, values}) do
    values
    |> map_while_ok(&render_string/1)
    |> case do
      {:ok, rendered} -> {:ok, "[" <> Enum.join(rendered, ", ") <> "]"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp render_string({:map, values}) do
    values
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      with {:ok, key} <- render_string(key),
           {:ok, value} <- render_string(value) do
        {:cont, {:ok, [{key, value} | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, pairs} ->
        rendered =
          pairs
          |> Enum.sort_by(fn {key, _value} -> key end)
          |> Enum.map_join(", ", fn {key, value} -> key <> ": " <> value end)

        {:ok, "{" <> rendered <> "}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp render_string({:type, type}), do: {:ok, type |> CType.from_input() |> CType.format()}
  defp render_string(value), do: string_clause_error(value)

  defp render_decimal({:int, value}), do: {:ok, Integer.to_string(value)}
  defp render_decimal({:uint, value}), do: {:ok, Integer.to_string(value)}

  defp render_decimal({:double, value}) when value in [:nan, :infinity, :negative_infinity],
    do: {:ok, double_to_string(value)}

  defp render_decimal(value),
    do:
      {:error,
       "error during formatting: decimal clause can only be used on integers, was given #{value_kind(value)}"}

  defp render_binary({:int, value}), do: {:ok, Integer.to_string(value, 2)}
  defp render_binary({:uint, value}), do: {:ok, Integer.to_string(value, 2)}
  defp render_binary({:bool, true}), do: {:ok, "1"}
  defp render_binary({:bool, false}), do: {:ok, "0"}

  defp render_binary(value),
    do:
      {:error,
       "error during formatting: only integers and bools can be formatted as binary, was given #{value_kind(value)}"}

  defp render_octal({:int, value}), do: {:ok, Integer.to_string(value, 8)}
  defp render_octal({:uint, value}), do: {:ok, Integer.to_string(value, 8)}

  defp render_octal(value),
    do:
      {:error,
       "error during formatting: octal clause can only be used on integers, was given #{value_kind(value)}"}

  defp render_hex({:int, value}, case_mode), do: {:ok, integer_hex(value, case_mode)}
  defp render_hex({:uint, value}, case_mode), do: {:ok, integer_hex(value, case_mode)}
  defp render_hex({:string, value}, case_mode), do: {:ok, bytes_hex(value, case_mode)}
  defp render_hex({:bytes, value}, case_mode), do: {:ok, bytes_hex(value, case_mode)}

  defp render_hex(value, _case_mode),
    do:
      {:error,
       "error during formatting: only integers, byte buffers, and strings can be formatted as hex, was given #{value_kind(value)}"}

  defp render_fixed({:double, value}, _precision)
       when value in [:nan, :infinity, :negative_infinity],
       do: {:ok, double_to_string(value)}

  defp render_fixed({:double, value}, precision), do: {:ok, fixed_decimal(value, precision)}

  defp render_fixed(value, _precision),
    do:
      {:error,
       "error during formatting: fixed-point clause can only be used on doubles, was given #{value_kind(value)}"}

  defp render_scientific({:double, value}, _precision)
       when value in [:nan, :infinity, :negative_infinity],
       do: {:ok, double_to_string(value)}

  defp render_scientific({:double, value}, precision),
    do: {:ok, scientific_decimal(value, precision)}

  defp render_scientific(value, _precision),
    do:
      {:error,
       "error during formatting: scientific clause can only be used on doubles, was given #{value_kind(value)}"}

  defp integer_hex(value, :lower), do: Integer.to_string(value, 16) |> String.downcase()
  defp integer_hex(value, :upper), do: Integer.to_string(value, 16) |> String.upcase()

  defp bytes_hex(value, case_mode) do
    value
    |> :binary.bin_to_list()
    |> Enum.map_join(fn byte ->
      byte
      |> Integer.to_string(16)
      |> maybe_case(case_mode)
      |> String.pad_leading(2, "0")
    end)
  end

  defp maybe_case(value, :lower), do: String.downcase(value)
  defp maybe_case(value, :upper), do: String.upcase(value)

  defp fixed_decimal(value, precision) do
    sign = if negative_float?(value), do: "-", else: ""
    body = fixed_decimal_abs(abs(value), precision)
    sign <> body
  end

  defp fixed_decimal_abs(value, precision) do
    scale = pow10(precision)
    rounded = round_half_even(value * scale)
    integer = div(rounded, scale)
    fraction = rem(rounded, scale)

    cond do
      precision == 0 ->
        Integer.to_string(integer)

      true ->
        Integer.to_string(integer) <>
          "." <>
          (fraction |> Integer.to_string() |> String.pad_leading(precision, "0"))
    end
  end

  defp scientific_decimal(value, precision) when value == 0.0 do
    fixed_decimal_abs(0.0, precision) <> "e+00"
  end

  defp scientific_decimal(value, precision) do
    sign = if negative_float?(value), do: "-", else: ""
    abs_value = abs(value)
    exponent = floor(:math.log10(abs_value))
    mantissa = abs_value / :math.pow(10, exponent)
    body = fixed_decimal_abs(mantissa, precision)

    {body, exponent} =
      if scientific_overflow?(body, precision) do
        {fixed_decimal_abs(1.0, precision), exponent + 1}
      else
        {body, exponent}
      end

    sign <> body <> "e" <> exponent_string(exponent)
  end

  defp scientific_overflow?(body, 0), do: body == "10"
  defp scientific_overflow?(body, _precision), do: String.starts_with?(body, "10.")

  defp exponent_string(exponent) do
    sign = if exponent < 0, do: "-", else: "+"
    sign <> (exponent |> abs() |> Integer.to_string() |> String.pad_leading(2, "0"))
  end

  defp pow10(precision) do
    Enum.reduce(1..precision//1, 1, fn _index, acc -> acc * 10 end)
  end

  defp round_half_even(value) do
    floor = floor(value)
    fraction = value - floor
    epsilon = 1.0e-12

    cond do
      fraction > 0.5 + epsilon -> floor + 1
      fraction < 0.5 - epsilon -> floor
      rem(floor, 2) == 0 -> floor
      true -> floor + 1
    end
  end

  defp negative_float?(value) do
    <<sign::1, _rest::63>> = <<value::float-64>>
    sign == 1
  end

  defp double_to_string(:nan), do: "NaN"
  defp double_to_string(:infinity), do: "Infinity"
  defp double_to_string(:negative_infinity), do: "-Infinity"
  defp double_to_string(value), do: :erlang.float_to_binary(value, [:short])

  defp string_clause_error(value) do
    {:error,
     "error during formatting: string clause can only be used on strings, bools, bytes, ints, doubles, maps, lists, types, durations, and timestamps, was given #{value_kind(value)}"}
  end

  defp value_kind(:null), do: "null_type"
  defp value_kind({:bool, _value}), do: "bool"
  defp value_kind({:int, _value}), do: "int"
  defp value_kind({:uint, _value}), do: "uint"
  defp value_kind({:double, _value}), do: "double"
  defp value_kind({:string, _value}), do: "string"
  defp value_kind({:bytes, _value}), do: "bytes"
  defp value_kind({:timestamp, _value}), do: "timestamp"
  defp value_kind({:duration, _value}), do: "duration"
  defp value_kind({:enum, name, _value}), do: name
  defp value_kind({:object, type_url, _value}), do: type_url
  defp value_kind({:message, name, _fields}), do: name
  defp value_kind({:type, _type}), do: "type"
  defp value_kind({:list, _values}), do: "list"
  defp value_kind({:map, _values}), do: "map"
  defp value_kind({:optional, _value}), do: "optional"
  defp value_kind(other), do: inspect(other)

  defp map_while_ok(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end
end
