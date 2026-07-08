# RobotsTxt

[![CI](https://github.com/ivan-podgurskiy/robots_txt/actions/workflows/ci.yml/badge.svg)](https://github.com/ivan-podgurskiy/robots_txt/actions/workflows/ci.yml)
[![Hex pm](https://img.shields.io/hexpm/v/robots_txt.svg)](https://hex.pm/packages/robots_txt)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/robots_txt)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An RFC 9309 robots.txt parser and matcher for Elixir, with Google-compatible
matching behavior and no runtime dependencies.

## Installation

Add `robots_txt` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:robots_txt, "~> 0.1"}
  ]
end
```

Or depend on the Git repository:

```elixir
{:robots_txt, git: "https://github.com/ivan-podgurskiy/robots_txt.git"}
```

## Quick start

```elixir
robots =
  RobotsTxt.parse("""
  User-agent: *
  Disallow: /private
  Allow: /private/preview
  Sitemap: https://example.com/sitemap.xml
  """)

RobotsTxt.allowed?(robots, "ExampleBot", "/private/report")
#=> false

RobotsTxt.matched_rule(robots, "ExampleBot", "/private/preview")
#=> {:allow, "/private/preview", 3}

RobotsTxt.sitemaps(robots)
#=> ["https://example.com/sitemap.xml"]
```

## Why

- Total, byte-oriented parsing accepts arbitrary binary input, including
  malformed UTF-8.
- Longest-match precedence, allow-on-tie behavior, wildcard matching, and
  specific-versus-global group selection follow Google-compatible behavior.
- Match decisions include the original pattern and source line number for
  diagnostics.
- The package has no runtime dependencies.

## What this library does not do

`RobotsTxt` does not fetch robots.txt files, follow redirects, cache results,
enforce crawl delays, or schedule crawler work. It also does not escape or
normalize request targets. Network policy and crawler coordination remain with
the caller.

The caller is responsible for fetching `/robots.txt` from the correct origin
and for applying the parsed rules only to that origin. Although absolute URLs
are accepted for matching convenience, their scheme, host, and port are not
used to determine scope.

For example, an application using Req can classify the final response before
parsing it. Req remains an application dependency, not a dependency of this
package:

```elixir
case Req.get("https://example.com/robots.txt") do
  {:ok, %{status: status, body: body}} ->
    case RobotsTxt.fetch_semantics(status) do
      :parse_body -> RobotsTxt.parse(body)
      :allow_all -> :allow_all
      :disallow_all -> :disallow_all
    end

  {:error, reason} ->
    {:fetch_error, reason}
end
```

Redirects must be resolved before passing the final status to
`RobotsTxt.fetch_semantics/1`.

## API

- `RobotsTxt.parse/1` and `RobotsTxt.parse/2` parse a binary document. Version
  0.1 accepts only an empty options list.
- `RobotsTxt.allowed?/3` returns the access decision for a crawler token and an
  escaped target.
- `RobotsTxt.matched_rule/3` returns `{:allow | :disallow, pattern, line}` or
  `:default`.
- `RobotsTxt.sitemaps/1` returns sitemap values in file order.
- `RobotsTxt.crawl_delay/2` returns the first parseable non-negative delay from
  the selected groups, but does not enforce it.
- `RobotsTxt.extensions/2` returns unknown directives for selected groups or
  global scope.
- `RobotsTxt.fetch_semantics/1` classifies a final HTTP response.
- `RobotsTxt.valid_user_agent?/1` validates a crawler product token.

See the [HexDocs API reference](https://hexdocs.pm/robots_txt/RobotsTxt.html)
for complete contracts and examples.

## Escaped-path contract

Targets passed to `allowed?/3` and `matched_rule/3` must already be RFC
3986-escaped. The matcher does not decode percent escapes or normalize paths,
so `/a/b` and `/a%2Fb` remain distinct.

Matching uses the path, parameters, and query. It ignores the fragment and, for
absolute URLs, the scheme, host, and port. A missing path is treated as `/`.

The crawler argument is a product token, not a complete HTTP `User-Agent`
header. It is compared case-insensitively with the leading valid product token
extracted from each file-side `User-agent` value.

## HTTP semantics cheat sheet

`fetch_semantics/1` accepts only a final response status:

| Final status | Result | Caller behavior |
| --- | --- | --- |
| `200..299` | `:parse_body` | Parse and apply the response body |
| `400..499` | `:allow_all` | Treat the robots.txt file as unavailable |
| `500..599` | `:disallow_all` | Temporarily treat the server as unavailable |

Resolve `1xx` and `3xx` responses before classification. Passing them to
`fetch_semantics/1` raises `FunctionClauseError`.

## Extensions

Sitemap directives are collected globally in file order. `Crawl-delay` is
available as optional metadata and is never enforced by the library.

Unknown directive names are lowercased and their values retain file order.
`extensions(robots, user_agent)` merges all selected specific groups, falling
back to selected global groups only when no specific group matches.
`extensions(robots, :global)` returns directives found outside groups.

## Compliance

The implementation passes all 378 standard cases and all 22 Google-specific
cases in the pinned Google robots.txt compliance harness. The exact harness
revision, prerequisites, invocation, and recorded result are in
[`test/compliance/README.md`](test/compliance/README.md).

Google-derived compatibility tests are identified in
[`NOTICE`](https://github.com/ivan-podgurskiy/robots_txt/blob/main/NOTICE).

## Roadmap

Planned follow-up work is tracked in the repository-only
[`ROADMAP.md`](https://github.com/ivan-podgurskiy/robots_txt/blob/main/ROADMAP.md).

## Development

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test --seed 0
mix credo --strict
mix dialyzer --format github
mix docs
```

## License

MIT © Ivan Podgurskiy. See [`LICENSE`](LICENSE).
