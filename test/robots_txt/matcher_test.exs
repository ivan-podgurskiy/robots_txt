defmodule RobotsTxt.MatcherTest do
  use ExUnit.Case, async: true

  alias RobotsTxt.Matcher

  test "path/1 extracts path, params, and query using Google semantics" do
    cases = [
      {"", "/"},
      {"http://www.example.com", "/"},
      {"http://www.example.com/", "/"},
      {"http://www.example.com/a", "/a"},
      {"http://www.example.com/a/", "/a/"},
      {"http://www.example.com/a/b?c=http://d.e/", "/a/b?c=http://d.e/"},
      {"http://www.example.com/a/b?c=d&e=f#fragment", "/a/b?c=d&e=f"},
      {"example.com", "/"},
      {"example.com/", "/"},
      {"example.com/a", "/a"},
      {"example.com/a/", "/a/"},
      {"example.com/a/b?c=d&e=f#fragment", "/a/b?c=d&e=f"},
      {"a", "/"},
      {"a/", "/"},
      {"/a", "/a"},
      {"a/b", "/b"},
      {"example.com?a", "/?a"},
      {"example.com/a;b#c", "/a;b"},
      {"//a/b/c", "/b/c"}
    ]

    for {target, expected} <- cases do
      assert Matcher.path(target) == expected
    end
  end

  test "longest matching rule wins and equal priority favors allow" do
    robots =
      RobotsTxt.parse("""
      User-agent: FooBot
      Disallow: /x/
      Allow: /x/page.html
      """)

    assert RobotsTxt.matched_rule(robots, "FooBot", "/x/page.html") ==
             {:allow, "/x/page.html", 3}

    assert RobotsTxt.allowed?(robots, "FooBot", "/x/page.html")
    refute RobotsTxt.allowed?(robots, "FooBot", "/x/other")

    tied = RobotsTxt.parse("User-agent: *\nDisallow: /same\nAllow: /same")
    assert RobotsTxt.matched_rule(tied, "OtherBot", "/same") == {:allow, "/same", 3}
  end

  test "specific groups suppress global groups even when no specific rule matches" do
    robots =
      RobotsTxt.parse("""
      User-agent: *
      Disallow: /
      User-agent: FooBot
      Disallow: /private
      """)

    assert RobotsTxt.matched_rule(robots, "FooBot", "/public") == :default
    assert RobotsTxt.allowed?(robots, "FooBot", "/public")
    refute RobotsTxt.allowed?(robots, "FooBot", "/private/page")
    refute RobotsTxt.allowed?(robots, "OtherBot", "/public")
  end

  test "file-side user agents are extracted while crawler tokens are not" do
    robots = RobotsTxt.parse("User-agent: Googlebot/2.1\nDisallow: /private")

    refute RobotsTxt.allowed?(robots, "Googlebot", "/private")
    assert RobotsTxt.allowed?(robots, "Googlebot/2.1", "/private")

    digit = RobotsTxt.parse("User-agent: Bot2\nDisallow: /")
    refute RobotsTxt.allowed?(digit, "Bot", "/")
    assert RobotsTxt.allowed?(digit, "Bot2", "/")
  end

  test "star followed by whitespace is a global user-agent" do
    robots = RobotsTxt.parse("User-agent: * baz\nDisallow: /")
    refute RobotsTxt.allowed?(robots, "AnyBot", "/")
  end

  test "rules from repeated matching groups are merged" do
    robots =
      RobotsTxt.parse("""
      User-agent: Foo
      Disallow: /one
      User-agent: Foo
      Disallow: /two
      """)

    refute RobotsTxt.allowed?(robots, "Foo", "/one")
    refute RobotsTxt.allowed?(robots, "Foo", "/two")
  end

  test "empty patterns have zero priority and decide nothing" do
    robots = RobotsTxt.parse("User-agent: *\nDisallow:\nAllow:")
    assert RobotsTxt.matched_rule(robots, "Bot", "/anything") == :default
    assert RobotsTxt.allowed?(robots, "Bot", "/anything")
  end

  test "allow index.html also allows the containing directory" do
    robots =
      RobotsTxt.parse("""
      User-agent: *
      Allow: /allowed/index.html
      Disallow: /
      """)

    assert RobotsTxt.allowed?(robots, "Bot", "/allowed/")
    assert RobotsTxt.allowed?(robots, "Bot", "/allowed/index.html")
    refute RobotsTxt.allowed?(robots, "Bot", "/allowed/index.htm")
  end

  test "absolute targets include query and ignore fragments" do
    robots = RobotsTxt.parse("User-agent: *\nDisallow: /search?q=secret$")

    refute RobotsTxt.allowed?(robots, "Bot", "https://example.com/search?q=secret#part")
    assert RobotsTxt.allowed?(robots, "Bot", "https://example.com/search?q=public")
  end

  test "no matching group or rule defaults to allowed" do
    robots = RobotsTxt.parse("User-agent: Foo\nDisallow: /")
    assert RobotsTxt.matched_rule(robots, "Bar", "/") == :default
    assert RobotsTxt.allowed?(robots, "Bar", "/")
  end
end
