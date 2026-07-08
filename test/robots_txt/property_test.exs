defmodule RobotsTxt.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias RobotsTxt.Pattern

  property "parse and match are total for arbitrary binaries" do
    check all(
            body <- binary(),
            user_agent <- binary(),
            target <- binary(),
            max_runs: 500
          ) do
      parsed = RobotsTxt.parse(body)

      assert is_boolean(RobotsTxt.allowed?(parsed, user_agent, target))
    end
  end

  property "pattern escaping is idempotent" do
    check all(pattern <- binary(), max_runs: 500) do
      escaped = Pattern.escape(pattern)

      assert Pattern.escape(escaped) == escaped
    end
  end

  property "allowed agrees with matched_rule" do
    check all(
            body <- binary(),
            user_agent <- binary(),
            target <- binary(),
            max_runs: 500
          ) do
      parsed = RobotsTxt.parse(body)

      disallowed? =
        match?({:disallow, _pattern, _line}, RobotsTxt.matched_rule(parsed, user_agent, target))

      assert RobotsTxt.allowed?(parsed, user_agent, target) == not disallowed?
    end
  end

  test "adversarial wildcard patterns complete without exponential backtracking" do
    path = String.duplicate("a", 4_096)
    pattern = String.duplicate("*a", 500)

    task = Task.async(fn -> Pattern.match?(path, pattern) end)

    case Task.yield(task, 2_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, true} -> assert true
      {:ok, false} -> flunk("expected the adversarial wildcard pattern to match")
      nil -> flunk("adversarial wildcard pattern exceeded the 2 second guard")
    end
  end
end
