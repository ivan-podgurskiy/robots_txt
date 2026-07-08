# Google robots.txt compliance harness

This directory contains the command adapter used by the external
`google/robotstxt-spec-test` harness.

## Pinned harness

- Repository: https://github.com/google/robotstxt-spec-test
- Revision: `552ade54b9ce6c121ffc462bceb26941749907a7`
- Prerequisites: Java 11, Maven, `protoc` 3.19.2, and a compiled local
  `robots_txt` project.

The pinned harness uses build plugins that are incompatible with recent JDKs,
and its protobuf runtime is pinned to 3.19.2. Using Java 11 and `protoc` 3.19.2
avoids build failures before the compliance tests begin.

## Adapter contract

The harness substitutes `%robots%`, `%url%`, and `%user-agent%` into the command.
`robots_cli.exs` reads the robots file as a binary, evaluates the URL for the
given user agent, and exits with:

- `0` when fetching is allowed
- `1` when fetching is disallowed
- `2` for diagnostic failures, such as invalid arguments or an unreadable file

## Running the harness

Compile this project from the project root:

```bash
MIX_ENV=dev mix compile
```

Build the pinned harness with matching tool versions:

```bash
JAVA_HOME=/absolute/path/to/jdk-11 \
  mvn compile -DprotocExecutable=/absolute/path/to/protoc-3.19.2
```

Then run Maven from the harness checkout, replacing the project and executable
paths with absolute paths:

```bash
PATH=/absolute/path/to/erlang/bin:$PATH \
JAVA_HOME=/absolute/path/to/jdk-11 \
mvn exec:java -Dexec.mainClass="com.google.search.robotstxt.spec.Main" \
  -Dexec.args="--command='/absolute/path/to/elixir -pa /absolute/project/path/_build/dev/lib/robots_txt/ebin /absolute/project/path/test/compliance/robots_cli.exs %robots% %url% %user-agent%' --outputType=EXITCODE"
```

Absolute Elixir and Erlang paths avoid directory-sensitive version-manager
shims when the harness launches the adapter from its own checkout.

## Verified result

Verified on July 8, 2026 against the pinned revision above:

- Compliance tests: 378 passed, 0 failed
- Google-specific tests: 22 passed, 0 failed
- Harness verdict: the parser follows the standard and adheres to Google's
  specifications
