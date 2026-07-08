# RobotsTxt roadmap

RFC 9309 robots.txt parsing and Google-compatible matching for Elixir, without
owning HTTP or crawler scheduling.

## What I wanted

- Parse arbitrary robots.txt binaries without turning malformed input into a
  document-level error.
- Match escaped paths and URLs with Google-compatible user-agent selection,
  wildcard handling, longest-rule precedence, and allow-on-tie behavior.
- Expose the deciding rule and source line for diagnostics.
- Preserve sitemaps, crawl delays, and unknown directives without enforcing
  non-standard policy.
- Keep fetching, redirects, caching, origin scoping, and scheduling in the
  caller.
- Ship with no runtime dependencies.

Out of scope for the first release: an HTTP client, cache, crawler scheduler,
automatic URL escaping, crawl-delay enforcement, and application-wide policy
storage.

## What v0.1.0 contains

- Total byte-oriented parsing with a bounded usable line length.
- Specific and global user-agent group selection compatible with Google
  robots.txt behavior.
- Escaped pattern matching with `*`, terminal `$`, longest-match precedence,
  and allow-on-tie decisions.
- Boolean decisions through `RobotsTxt.allowed?/3` and inspectable decisions
  through `RobotsTxt.matched_rule/3`.
- Sitemap, crawl-delay, and extension accessors with deterministic file-order
  semantics.
- Final-response HTTP classification through `RobotsTxt.fetch_semantics/1`.
- Unit, doctest, property, Google-derived, and pinned external compliance
  coverage.
- ExDoc, Credo, Dialyzer, CI, and Hex package metadata.

## What's next

- Track upstream robots.txt compliance cases and add regressions for meaningful
  behavioral changes.
- Add reproducible performance and memory benchmarks for large and adversarial
  inputs.
- Evaluate a broader supported Elixir and OTP range from real-world demand.
- Keep new integrations optional so the core parser and matcher retain zero
  runtime dependencies.
