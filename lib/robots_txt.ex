defmodule RobotsTxt do
  @moduledoc """
  Parses robots.txt files and evaluates crawler access rules.

  `RobotsTxt` is the package's complete public API. It parses a robots.txt body
  into an inspectable value and, once matching is applied, answers whether a
  crawler may fetch a path or URL.

  The library is deliberately limited to parsing and matching. It does not
  fetch robots.txt files, follow redirects, cache responses, enforce crawl
  delays, or schedule crawler work. Those responsibilities remain with the
  caller.

  ## Parsing

  Parsing is total for binary input. A malformed line does not invalidate the
  document: unsupported syntax is skipped and unknown directives are retained
  as extensions.

      iex> robots = RobotsTxt.parse("User-agent: ExampleBot\\nDisallow: /private")
      iex> length(robots.groups)
      1

  ## Representation

  The fields in `t:t/0` are public for inspection and debugging. Their exact
  representation may change before version 1.0, so application behavior should
  use the accessor functions rather than depending on nested structs.
  """

  alias RobotsTxt.Group

  defstruct groups: [], sitemaps: [], global_extensions: %{}

  @typedoc """
  A parsed robots.txt document.

  `groups` preserves group order, `sitemaps` preserves file order, and
  `global_extensions` contains unknown directives found outside a group.
  """
  @type t :: %__MODULE__{
          groups: [Group.t()],
          sitemaps: [binary()],
          global_extensions: %{optional(binary()) => [binary()]}
        }

  @doc """
  Parses a robots.txt body.

  The parser works byte-by-byte and accepts arbitrary binaries, including
  invalid UTF-8. Malformed lines are skipped, while recognized lines before and
  after them continue to be processed.

  Version 0.1 accepts no options. Passing a non-keyword value or any option
  raises `ArgumentError`; the optional argument exists to keep the API arity
  stable for future versions.

  ## Examples

      iex> robots = RobotsTxt.parse("Sitemap: https://example.com/sitemap.xml")
      iex> robots.sitemaps
      ["https://example.com/sitemap.xml"]

      iex> RobotsTxt.parse(<<255, 0, 1>>)
      %RobotsTxt{groups: [], sitemaps: [], global_extensions: %{}}
  """
  @spec parse(binary(), keyword()) :: t()
  def parse(body, opts \\ []) when is_binary(body) do
    cond do
      not is_list(opts) or not Keyword.keyword?(opts) ->
        raise ArgumentError, "options must be a keyword list"

      opts != [] ->
        raise ArgumentError, "unknown options: #{inspect(Keyword.keys(opts))}"

      true ->
        RobotsTxt.Parser.parse(body)
    end
  end

  @doc """
  Classifies a final HTTP response according to RFC 9309 fetch semantics.

  The result tells an integration whether to parse the response body, allow all
  crawling because the file is unavailable, or temporarily disallow crawling
  because the server is unavailable.

  Informational and redirect responses are intentionally outside this
  function's domain. The caller must follow redirects before classifying the
  final response. Passing a 1xx, 3xx, or out-of-range status raises
  `FunctionClauseError`.

  ## Examples

      iex> RobotsTxt.fetch_semantics(200)
      :parse_body

      iex> RobotsTxt.fetch_semantics(404)
      :allow_all

      iex> RobotsTxt.fetch_semantics(503)
      :disallow_all
  """
  @spec fetch_semantics(200..299 | 400..499 | 500..599) ::
          :parse_body | :allow_all | :disallow_all
  def fetch_semantics(status) when status in 200..299, do: :parse_body
  def fetch_semantics(status) when status in 400..499, do: :allow_all
  def fetch_semantics(status) when status in 500..599, do: :disallow_all

  @doc """
  Returns whether a crawler product token can match a specific robots group.

  A valid token is non-empty and contains only ASCII letters, `-`, and `_`.
  Digits, spaces, version suffixes, wildcards, and non-ASCII bytes are invalid.

  This helper validates the crawler-side product token supplied by an
  integration. It does not validate an entire HTTP `User-Agent` header.

  ## Examples

      iex> RobotsTxt.valid_user_agent?("ExampleBot")
      true

      iex> RobotsTxt.valid_user_agent?("ExampleBot/1.0")
      false

      iex> RobotsTxt.valid_user_agent?("Bot2")
      false
  """
  @spec valid_user_agent?(term()) :: boolean()
  def valid_user_agent?(value) when is_binary(value) and byte_size(value) > 0 do
    valid_user_agent_bytes?(value)
  end

  def valid_user_agent?(_value), do: false

  defp valid_user_agent_bytes?(<<>>), do: true

  defp valid_user_agent_bytes?(<<char, rest::binary>>)
       when char in ?A..?Z or char in ?a..?z or char in [?-, ?_] do
    valid_user_agent_bytes?(rest)
  end

  defp valid_user_agent_bytes?(_value), do: false
end
