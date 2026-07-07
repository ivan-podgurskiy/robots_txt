defmodule RobotsTxt.ParserTest do
  use ExUnit.Case, async: true

  alias RobotsTxt.Group

  test "parse/2 rejects unsupported options" do
    assert_raise ArgumentError, ~r/unknown options/, fn -> RobotsTxt.parse("", mode: :strict) end

    assert_raise ArgumentError, ~r/options must be a keyword list/, fn ->
      RobotsTxt.parse("", [:bad])
    end
  end

  test "comments and blank lines do not split a group" do
    parsed = RobotsTxt.parse("User-agent: A\n# note\n\nDisallow: /private # trailing")

    assert [%Group{user_agents: ["A"], rules: [rule]}] = parsed.groups
    assert %{action: :disallow, pattern: "/private", escaped: "/private", line: 4} = rule
  end

  test "multiple user agents share a rule block" do
    parsed =
      RobotsTxt.parse(
        "User-agent: GPTBot\nUser-agent: anthropic-ai\nUser-agent: ClaudeBot\nDisallow: /"
      )

    assert [%Group{user_agents: ["GPTBot", "anthropic-ai", "ClaudeBot"]}] = parsed.groups
  end

  test "sitemap and unknown directives do not close user-agent collection" do
    body = "User-agent: A\nSitemap: https://x/s.xml\nX-Test: one\nUser-agent: B\nDisallow: /"
    parsed = RobotsTxt.parse(body)

    assert [%Group{user_agents: ["A", "B"], rules: [rule], extensions: extensions}] =
             parsed.groups

    assert rule.action == :disallow
    assert rule.pattern == "/"
    assert extensions == %{"x-test" => ["one"]}
    assert parsed.sitemaps == ["https://x/s.xml"]
  end

  test "orphan rules are ignored and orphan unknown directives are global" do
    parsed =
      RobotsTxt.parse("Disallow: /ignored\nContent-Signal: ai-train=no\nUser-agent: A\nAllow: /")

    assert [%Group{rules: [%{action: :allow}]}] = parsed.groups
    assert parsed.global_extensions == %{"content-signal" => ["ai-train=no"]}
  end

  test "CR, LF, and CRLF produce one-based source lines" do
    parsed = RobotsTxt.parse("User-agent: A\r\nAllow: /a\rDisallow: /b\nAllow: /c")

    assert [%Group{rules: rules}] = parsed.groups
    assert Enum.map(rules, & &1.line) == [2, 3, 4]
  end

  test "full and partial BOM prefixes are consumed" do
    for prefix <- [<<0xEF>>, <<0xEF, 0xBB>>, <<0xEF, 0xBB, 0xBF>>] do
      assert [%Group{user_agents: ["A"]}] = RobotsTxt.parse(prefix <> "User-agent: A").groups
    end

    assert RobotsTxt.parse(<<0xEF, 0xBA, "User-agent: A">>).groups == []
  end

  test "keys use prefix matching and supported frequent typos" do
    for key <- [
          "Disallow",
          "Disallowed",
          "Dissallow",
          "Dissalow",
          "Disalow",
          "Diasllow",
          "Disallaw"
        ] do
      parsed = RobotsTxt.parse("User-agent: A\n#{key}: /x")
      assert [%Group{rules: [%{action: :disallow, pattern: "/x"}]}] = parsed.groups
    end

    parsed = RobotsTxt.parse("Useragent: A\nAllowExtra: /x\nSite-map: https://x/s.xml")
    assert [%Group{rules: [%{action: :allow}]}] = parsed.groups
    assert parsed.sitemaps == ["https://x/s.xml"]
  end

  test "missing colon is accepted only for exactly two tokens" do
    parsed = RobotsTxt.parse("user-agent A\ndisallow /x\nfoo bar baz")

    assert [%Group{user_agents: ["A"], rules: [%{pattern: "/x"}], extensions: %{}}] =
             parsed.groups
  end

  test "overlong lines are truncated and the following line remains intact" do
    body =
      "User-agent: *\nDisallow: /" <>
        String.duplicate("x", 20_000) <> "\nAllow: /ok"

    assert [%Group{rules: [disallow, allow]}] = RobotsTxt.parse(body).groups
    assert byte_size("Disallow: " <> disallow.pattern) == 16_663
    assert allow.pattern == "/ok"
  end

  test "pattern values are escaped once while extensions remain raw" do
    body = <<"User-agent: A\nDisallow: /caf", 0xC3, 0xA9, "\nContent-Signal: /caf", 0xC3, 0xA9>>
    assert [%Group{rules: [rule], extensions: extensions}] = RobotsTxt.parse(body).groups
    assert rule.escaped == "/caf%C3%A9"
    assert extensions == %{"content-signal" => [<<"/caf", 0xC3, 0xA9>>]}
  end
end
