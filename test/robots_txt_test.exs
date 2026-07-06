defmodule RobotsTxtTest do
  use ExUnit.Case, async: true
  doctest RobotsTxt

  test "fetch_semantics/1 maps final response classes" do
    assert RobotsTxt.fetch_semantics(200) == :parse_body
    assert RobotsTxt.fetch_semantics(299) == :parse_body
    assert RobotsTxt.fetch_semantics(401) == :allow_all
    assert RobotsTxt.fetch_semantics(499) == :allow_all
    assert RobotsTxt.fetch_semantics(500) == :disallow_all
    assert RobotsTxt.fetch_semantics(599) == :disallow_all
    assert_raise FunctionClauseError, fn -> RobotsTxt.fetch_semantics(302) end
  end

  test "valid_user_agent?/1 accepts only non-empty ASCII product tokens" do
    assert RobotsTxt.valid_user_agent?("ClaudeBot")
    assert RobotsTxt.valid_user_agent?("Foo_Bar")
    refute RobotsTxt.valid_user_agent?("")
    refute RobotsTxt.valid_user_agent?("Bot2")
    refute RobotsTxt.valid_user_agent?("Foo Bar")
    refute RobotsTxt.valid_user_agent?(<<255>>)
  end
end
