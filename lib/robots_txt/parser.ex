defmodule RobotsTxt.Parser do
  @moduledoc """
  Byte-oriented parser used by `RobotsTxt.parse/2`.

  The parser performs a single line-oriented pass. It reproduces compatibility
  behavior such as partial BOM consumption, CR/LF handling, the 16,663-byte
  usable line cap, case-insensitive prefix keys, accepted directive typos, and
  user-agent group boundaries.

  Invalid UTF-8 and malformed lines are ordinary input, not parser errors. This
  module is an implementation detail; use `RobotsTxt.parse/2` in application
  code.
  """

  alias RobotsTxt.Group
  alias RobotsTxt.Pattern
  alias RobotsTxt.Rule

  @max_line_bytes 16_663

  @doc """
  Parses a robots.txt body into a `RobotsTxt` struct.

  This lower-level entry point assumes options were already validated by
  `RobotsTxt.parse/2`.

  ## Example

      iex> parsed = RobotsTxt.Parser.parse("User-agent: ExampleBot")
      iex> [%RobotsTxt.Group{user_agents: ["ExampleBot"]}] = parsed.groups
      iex> parsed.sitemaps
      []
  """
  @spec parse(binary()) :: RobotsTxt.t()
  def parse(body) when is_binary(body) do
    state = %{
      groups: [],
      agents: [],
      rules: [],
      crawl_delays: [],
      extensions: %{},
      sitemaps: [],
      global_extensions: %{},
      separator?: false
    }

    body
    |> scan([], 0, 0, false, 0, state)
    |> finalize_group()
    |> build_result()
  end

  defp scan(<<0xEF, rest::binary>>, line, count, 0, last_cr, line_number, state) do
    scan(rest, line, count, 1, last_cr, line_number, state)
  end

  defp scan(<<0xBB, rest::binary>>, line, count, 1, last_cr, line_number, state) do
    scan(rest, line, count, 2, last_cr, line_number, state)
  end

  defp scan(<<0xBF, rest::binary>>, line, count, 2, last_cr, line_number, state) do
    scan(rest, line, count, 3, last_cr, line_number, state)
  end

  defp scan(<<byte, rest::binary>>, line, count, bom_position, last_cr, line_number, state)
       when bom_position < 3 do
    scan_byte(rest, byte, line, count, last_cr, line_number, state)
  end

  defp scan(<<byte, rest::binary>>, line, count, 3, last_cr, line_number, state) do
    scan_byte(rest, byte, line, count, last_cr, line_number, state)
  end

  defp scan(<<>>, line, _count, _bom_position, _last_cr, line_number, state) do
    emit_line(line, line_number + 1, state)
  end

  defp scan_byte(rest, byte, line, _count, last_cr, line_number, state)
       when byte in [0x0A, 0x0D] do
    continuation? = line == [] and last_cr and byte == 0x0A

    if continuation? do
      scan(rest, [], 0, 3, false, line_number, state)
    else
      next_line = line_number + 1
      next_state = emit_line(line, next_line, state)
      scan(rest, [], 0, 3, byte == 0x0D, next_line, next_state)
    end
  end

  defp scan_byte(rest, byte, line, count, last_cr, line_number, state) do
    if count < @max_line_bytes do
      scan(rest, [byte | line], count + 1, 3, last_cr, line_number, state)
    else
      scan(rest, line, count, 3, last_cr, line_number, state)
    end
  end

  defp emit_line(line, line_number, state) do
    line
    |> Enum.reverse()
    |> :erlang.list_to_binary()
    |> parse_line()
    |> fold_directive(line_number, state)
  end

  defp parse_line(line) do
    line
    |> strip_comment()
    |> trim_ascii()
    |> split_key_value()
    |> classify_directive()
  end

  defp strip_comment(line) do
    case :binary.match(line, "#") do
      {position, 1} -> binary_part(line, 0, position)
      :nomatch -> line
    end
  end

  defp split_key_value(<<>>), do: :ignore

  defp split_key_value(line) do
    case :binary.match(line, ":") do
      {position, 1} ->
        key = line |> binary_part(0, position) |> trim_ascii()
        value = line |> binary_part(position + 1, byte_size(line) - position - 1) |> trim_ascii()
        key_value(key, value)

      :nomatch ->
        split_on_whitespace(line)
    end
  end

  defp split_on_whitespace(line) do
    case :binary.match(line, [" ", "\t"]) do
      {position, 1} ->
        key = line |> binary_part(0, position) |> trim_ascii()
        value = line |> binary_part(position + 1, byte_size(line) - position - 1) |> trim_ascii()

        if value != <<>> and :binary.match(value, [" ", "\t"]) == :nomatch do
          key_value(key, value)
        else
          :ignore
        end

      :nomatch ->
        :ignore
    end
  end

  defp key_value(<<>>, _value), do: :ignore
  defp key_value(key, value), do: {ascii_downcase(key), value}

  defp classify_directive(:ignore), do: :ignore

  defp classify_directive({key, value}) do
    cond do
      prefix?(key, "user-agent") or prefix?(key, "useragent") or prefix?(key, "user agent") ->
        {:user_agent, value}

      prefix?(key, "allow") ->
        {:allow, value}

      prefix?(key, "disallow") or prefix?(key, "dissallow") or
        prefix?(key, "dissalow") or prefix?(key, "disalow") or
        prefix?(key, "diasllow") or prefix?(key, "disallaw") ->
        {:disallow, value}

      prefix?(key, "sitemap") or prefix?(key, "site-map") ->
        {:sitemap, value}

      true ->
        {:unknown, key, value}
    end
  end

  defp prefix?(value, prefix) when byte_size(value) >= byte_size(prefix) do
    binary_part(value, 0, byte_size(prefix)) == prefix
  end

  defp prefix?(_value, _prefix), do: false

  defp fold_directive(:ignore, _line_number, state), do: state

  defp fold_directive({:user_agent, value}, _line_number, %{separator?: true} = state) do
    state
    |> finalize_group()
    |> add_user_agent(value)
  end

  defp fold_directive({:user_agent, value}, _line_number, state) do
    add_user_agent(state, value)
  end

  defp fold_directive({action, value}, line_number, %{agents: [_ | _]} = state)
       when action in [:allow, :disallow] do
    rule = %Rule{
      action: action,
      pattern: value,
      escaped: Pattern.escape(value),
      line: line_number
    }

    %{state | rules: [rule | state.rules], separator?: true}
  end

  defp fold_directive({action, _value}, _line_number, state)
       when action in [:allow, :disallow],
       do: state

  defp fold_directive({:sitemap, value}, _line_number, state) do
    %{state | sitemaps: [value | state.sitemaps]}
  end

  defp fold_directive({:unknown, "crawl-delay", value}, _line_number, %{agents: [_ | _]} = state) do
    %{state | crawl_delays: [value | state.crawl_delays]}
  end

  defp fold_directive({:unknown, key, value}, _line_number, %{agents: []} = state) do
    %{state | global_extensions: prepend_value(state.global_extensions, key, value)}
  end

  defp fold_directive({:unknown, key, value}, _line_number, state) do
    %{state | extensions: prepend_value(state.extensions, key, value)}
  end

  defp add_user_agent(state, value), do: %{state | agents: [value | state.agents]}

  defp prepend_value(values, key, value) do
    Map.update(values, key, [value], &[value | &1])
  end

  defp finalize_group(%{agents: []} = state), do: state

  defp finalize_group(state) do
    group = %Group{
      user_agents: Enum.reverse(state.agents),
      rules: Enum.reverse(state.rules),
      crawl_delays: Enum.reverse(state.crawl_delays),
      extensions: reverse_values(state.extensions)
    }

    %{
      state
      | groups: [group | state.groups],
        agents: [],
        rules: [],
        crawl_delays: [],
        extensions: %{},
        separator?: false
    }
  end

  defp build_result(state) do
    %RobotsTxt{
      groups: Enum.reverse(state.groups),
      sitemaps: Enum.reverse(state.sitemaps),
      global_extensions: reverse_values(state.global_extensions)
    }
  end

  defp reverse_values(values) do
    Map.new(values, fn {key, entries} -> {key, Enum.reverse(entries)} end)
  end

  defp ascii_downcase(value) do
    for <<byte <- value>>, into: <<>> do
      if byte in ?A..?Z, do: <<byte + 32>>, else: <<byte>>
    end
  end

  defp trim_ascii(value) do
    value
    |> trim_ascii_left()
    |> trim_ascii_right()
  end

  defp trim_ascii_left(<<byte, rest::binary>>) when byte in [9, 10, 11, 12, 13, 32],
    do: trim_ascii_left(rest)

  defp trim_ascii_left(value), do: value

  defp trim_ascii_right(<<>>), do: <<>>

  defp trim_ascii_right(value) do
    last_position = byte_size(value) - 1

    if :binary.at(value, last_position) in [9, 10, 11, 12, 13, 32] do
      value |> binary_part(0, last_position) |> trim_ascii_right()
    else
      value
    end
  end
end
