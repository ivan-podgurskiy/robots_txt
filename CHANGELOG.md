# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-08

### Added

- Eight-function public API for parsing robots.txt documents, evaluating
  access, inspecting the deciding rule, reading sitemaps and crawl delays,
  retaining extensions, classifying final HTTP responses, and validating
  crawler product tokens.
- Google-compatible group selection, wildcard matching, longest-rule
  precedence, allow-on-tie decisions, directive aliases, and line-length
  handling.
- Total parsing for arbitrary binary input and source-line metadata for match
  decisions.
- File-ordered sitemap and extension access, including deterministic merging
  across selected groups.
- Unit, doctest, property, and Google-derived compatibility coverage, plus a
  pinned external compliance harness with 378 standard and 22 Google-specific
  cases passing.
- A zero-runtime-dependency package with explicit boundaries around fetching,
  redirects, caching, escaping, host scoping, and crawl-delay enforcement.

[0.1.0]: https://github.com/ivan-podgurskiy/robots_txt/releases/tag/v0.1.0
