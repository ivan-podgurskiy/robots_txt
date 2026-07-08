defmodule RobotsTxt do
  @moduledoc """
  Parses robots.txt files and evaluates crawler access rules.

  `RobotsTxt` is the package's complete public API. It parses a robots.txt body
  into an inspectable value and, once matching is applied, answers whether a
  crawler may fetch a path or URL.

  The library is deliberately limited to parsing and matching. It does not
  fetch robots.txt files, follow redirects, cache responses, enforce crawl
  delays, or schedule crawler work. Those responsibilities remain with the
  caller. The caller must also scope each parsed file to the origin from which
  it was fetched.

  Matching uses a caller-supplied crawler product token, not a complete HTTP
  `User-Agent` header. File-side `User-agent` values are reduced to their
  leading ASCII product token before a case-insensitive comparison; the
  caller-supplied token is compared as-is.

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
  Returns the rule that decides whether `user_agent` may fetch `target`.

  `target` may be an escaped path or an absolute URL. Only its path, parameters,
  and query participate in matching; scheme, host, port, and fragment are
  ignored. The caller must provide an RFC 3986-escaped target and ensure that
  the parsed file belongs to the target's origin.

  Returns `:default` when no positive-priority rule decides the request. Default
  access is allowed. A returned tuple contains the action, the original
  file-side pattern, and its one-based source line number.

  ## Examples

      iex> robots = RobotsTxt.parse("User-agent: *\\nDisallow: /private")
      iex> RobotsTxt.matched_rule(robots, "ExampleBot", "/private/page")
      {:disallow, "/private", 2}
      iex> RobotsTxt.matched_rule(robots, "ExampleBot", "/public")
      :default
  """
  @spec matched_rule(t(), binary(), binary()) ::
          {:allow | :disallow, binary(), pos_integer()} | :default
  def matched_rule(%__MODULE__{} = robots, user_agent, target)
      when is_binary(user_agent) and is_binary(target) do
    RobotsTxt.Matcher.matched_rule(robots, user_agent, target)
  end

  @doc """
  Returns whether `user_agent` may fetch `target`.

  This is a boolean wrapper around `matched_rule/3`. A matching disallow rule
  returns `false`; an allow rule or `:default` returns `true`.

  ## Examples

      iex> robots = RobotsTxt.parse("User-agent: *\\nDisallow: /private")
      iex> RobotsTxt.allowed?(robots, "ExampleBot", "/private/page")
      false
      iex> RobotsTxt.allowed?(robots, "ExampleBot", "https://example.com/public")
      true
  """
  @spec allowed?(t(), binary(), binary()) :: boolean()
  def allowed?(%__MODULE__{} = robots, user_agent, target)
      when is_binary(user_agent) and is_binary(target) do
    case matched_rule(robots, user_agent, target) do
      {:disallow, _pattern, _line} -> false
      {:allow, _pattern, _line} -> true
      :default -> true
    end
  end

  @doc """
  Returns all sitemap values in file order.

  Sitemap directives are independent of user-agent groups. Values are returned
  exactly as parsed after comment removal and surrounding whitespace trimming.

  ## Example

      iex> robots = RobotsTxt.parse("Sitemap: https://example.com/sitemap.xml")
      iex> RobotsTxt.sitemaps(robots)
      ["https://example.com/sitemap.xml"]
  """
  @spec sitemaps(t()) :: [binary()]
  def sitemaps(%__MODULE__{sitemaps: sitemaps}), do: sitemaps

  @doc """
  Returns the first parseable non-negative crawl delay for `user_agent`.

  Crawl delay is not part of RFC 9309 and is never enforced by this library.
  Matching specific groups take precedence over global groups, and repeated
  matching groups are inspected in file order. Returns `nil` when no selected
  group contains a complete non-negative integer or float value.

  ## Examples

      iex> robots = RobotsTxt.parse("User-agent: *\\nCrawl-delay: 1.5")
      iex> RobotsTxt.crawl_delay(robots, "ExampleBot")
      1.5

      iex> RobotsTxt.crawl_delay(RobotsTxt.parse(""), "ExampleBot")
      nil
  """
  @spec crawl_delay(t(), binary()) :: number() | nil
  def crawl_delay(%__MODULE__{} = robots, user_agent) when is_binary(user_agent) do
    robots
    |> RobotsTxt.Matcher.selected_groups(user_agent)
    |> Enum.find_value(fn group -> Enum.find_value(group.crawl_delays, &parse_delay/1) end)
  end

  @doc """
  Returns unknown directives associated with a selected group or global scope.

  Directive names are lowercased. Values are raw apart from comment removal and
  surrounding whitespace trimming, and remain in file order. Passing a crawler
  token uses the same specific-over-global group selection as `allowed?/3`;
  passing `:global` returns directives found outside every group.

  ## Examples

      iex> robots = RobotsTxt.parse("Content-Signal: ai-train=no")
      iex> RobotsTxt.extensions(robots, :global)
      %{"content-signal" => ["ai-train=no"]}

      iex> robots = RobotsTxt.parse("User-agent: *\\nX-Policy: one")
      iex> RobotsTxt.extensions(robots, "ExampleBot")
      %{"x-policy" => ["one"]}
  """
  @spec extensions(t(), binary() | :global) :: %{optional(binary()) => [binary()]}
  def extensions(%__MODULE__{global_extensions: extensions}, :global), do: extensions

  def extensions(%__MODULE__{} = robots, user_agent) when is_binary(user_agent) do
    robots
    |> RobotsTxt.Matcher.selected_groups(user_agent)
    |> Enum.reduce(%{}, fn group, merged -> merge_extensions(merged, group.extensions) end)
  end

  defp merge_extensions(merged, extensions) do
    Map.merge(merged, extensions, fn _key, earlier, later -> earlier ++ later end)
  end

  defp parse_delay(value) do
    case Integer.parse(value) do
      {delay, ""} when delay >= 0 -> delay
      _result -> parse_float_delay(value)
    end
  end

  defp parse_float_delay(value) do
    case Float.parse(value) do
      {delay, ""} when delay >= 0 -> delay
      _result -> nil
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
