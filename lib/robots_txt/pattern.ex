defmodule RobotsTxt.Pattern do
  @moduledoc """
  Byte-oriented robots.txt pattern normalization and matching.

  Matching follows Google's position-set algorithm. It supports `*` as a
  wildcard and treats `$` as an end anchor only when it is the final pattern
  byte. It does not decode or normalize the target path.

  This module is an implementation detail. Callers should use the matching
  functions exposed by `RobotsTxt` rather than depend on it directly.
  """

  import Bitwise

  @doc """
  Canonicalizes a rule pattern for matching.

  Existing `%XX` sequences are preserved with uppercase hex digits. Bytes at
  or above `0x80` are percent-encoded, while all other bytes are copied as-is.
  The operation is idempotent and never decodes input.

  ## Examples

      iex> RobotsTxt.Pattern.escape("/a%2f")
      "/a%2F"

      iex> RobotsTxt.Pattern.escape(<<"/caf", 0xC3, 0xA9>>)
      "/caf%C3%A9"
  """
  @spec escape(binary()) :: binary()
  def escape(value) when is_binary(value) do
    value
    |> escape([])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  @doc """
  Returns whether an escaped path matches a canonical rule pattern.

  Patterns are anchored at the start. Reaching the end of a pattern is a match
  even when bytes remain in the path, unless the pattern ends with `$`.

  ## Examples

      iex> RobotsTxt.Pattern.match?("/private/page", "/private/")
      true

      iex> RobotsTxt.Pattern.match?("/private/page", "/private/$")
      false

      iex> RobotsTxt.Pattern.match?("/a/x/b", "/a/*/b$")
      true
  """
  @spec match?(binary(), binary()) :: boolean()
  def match?(path, pattern) when is_binary(path) and is_binary(pattern) do
    match_pattern(path, pattern, [0], byte_size(path))
  end

  defguardp is_hex(char)
            when char in ?0..?9 or char in ?A..?F or char in ?a..?f

  defp escape(<<"%", first, second, rest::binary>>, acc)
       when is_hex(first) and is_hex(second) do
    escape(rest, [[?%, uppercase_hex(first), uppercase_hex(second)] | acc])
  end

  defp escape(<<byte, rest::binary>>, acc) when byte >= 0x80 do
    escape(rest, [[?%, hex_digit(byte >>> 4), hex_digit(byte &&& 0x0F)] | acc])
  end

  defp escape(<<byte, rest::binary>>, acc), do: escape(rest, [byte | acc])
  defp escape(<<>>, acc), do: acc

  defp uppercase_hex(char) when char in ?a..?f, do: char - 32
  defp uppercase_hex(char), do: char

  defp hex_digit(value) when value < 10, do: ?0 + value
  defp hex_digit(value), do: ?A + value - 10

  defp match_pattern(_path, <<>>, positions, _path_length), do: positions != []

  defp match_pattern(_path, <<"$">>, positions, path_length) do
    List.last(positions) == path_length
  end

  defp match_pattern(path, <<"*", rest::binary>>, [first | _positions], path_length) do
    match_pattern(path, rest, Enum.to_list(first..path_length), path_length)
  end

  defp match_pattern(path, <<literal, rest::binary>>, positions, path_length) do
    advanced =
      Enum.reduce(positions, [], fn position, acc ->
        if position < path_length and :binary.at(path, position) == literal do
          [position + 1 | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()

    case advanced do
      [] -> false
      _positions -> match_pattern(path, rest, advanced, path_length)
    end
  end
end
