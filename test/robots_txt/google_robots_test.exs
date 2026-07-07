# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Adapted from google/robotstxt robots_test.cc at revision
# 22b355ff855419e6a3ff8ff09c0ad7fdb17116f9.

defmodule RobotsTxt.GoogleRobotsTest do
  use ExUnit.Case, async: true

  alias RobotsTxt.Matcher
  alias RobotsTxt.Pattern

  defp allowed?(body, user_agent, target) do
    body |> RobotsTxt.parse() |> RobotsTxt.allowed?(user_agent, target)
  end

  defp assert_allowed(body, user_agent, targets) do
    Enum.each(
      targets,
      &assert(allowed?(body, user_agent, &1), "expected #{inspect(&1)} to be allowed")
    )
  end

  defp assert_disallowed(body, user_agent, targets) do
    Enum.each(
      targets,
      &refute(allowed?(body, user_agent, &1), "expected #{inspect(&1)} to be disallowed")
    )
  end

  # GoogleOnly_SystemTest
  test "GoogleOnly_SystemTest" do
    body = "user-agent: FooBot\ndisallow: /\n"

    assert allowed?("", "FooBot", "")
    assert allowed?(body, "", "")
    refute allowed?(body, "FooBot", "")
    assert allowed?("", "", "")
  end

  # ID_LineSyntax_Line
  test "ID_LineSyntax_Line" do
    correct = "user-agent: FooBot\ndisallow: /\n"
    incorrect = "foo: FooBot\nbar: /\n"
    accepted = "user-agent FooBot\ndisallow /\n"
    target = "http://foo.bar/x/y"

    refute allowed?(correct, "FooBot", target)
    assert allowed?(incorrect, "FooBot", target)
    refute allowed?(accepted, "FooBot", target)
  end

  # ID_LineSyntax_Groups
  test "ID_LineSyntax_Groups" do
    body =
      "allow: /foo/bar/\n\n" <>
        "user-agent: FooBot\ndisallow: /\nallow: /x/\n" <>
        "user-agent: BarBot\ndisallow: /\nallow: /y/\n\n\nallow: /w/\n" <>
        "user-agent: BazBot\n\nuser-agent: FooBot\nallow: /z/\ndisallow: /\n"

    assert_allowed(body, "FooBot", ["http://foo.bar/x/b", "http://foo.bar/z/d"])
    assert_disallowed(body, "FooBot", ["http://foo.bar/y/c"])
    assert_allowed(body, "BarBot", ["http://foo.bar/y/c", "http://foo.bar/w/a"])
    assert_disallowed(body, "BarBot", ["http://foo.bar/z/d"])
    assert_allowed(body, "BazBot", ["http://foo.bar/z/d"])

    for agent <- ["FooBot", "BarBot", "BazBot"] do
      refute allowed?(body, agent, "http://foo.bar/foo/bar/")
    end
  end

  # ID_LineSyntax_Groups_OtherRules
  test "ID_LineSyntax_Groups_OtherRules" do
    sitemap = "User-agent: BarBot\nSitemap: https://foo.bar/sitemap\nUser-agent: *\nDisallow: /\n"
    unknown = "User-agent: FooBot\nInvalid-Unknown-Line: unknown\nUser-agent: *\nDisallow: /\n"

    assert_disallowed(sitemap, "FooBot", ["http://foo.bar/"])
    assert_disallowed(sitemap, "BarBot", ["http://foo.bar/"])
    assert_disallowed(unknown, "FooBot", ["http://foo.bar/"])
    assert_disallowed(unknown, "BarBot", ["http://foo.bar/"])
  end

  # ID_REPLineNamesCaseInsensitive
  test "ID_REPLineNamesCaseInsensitive" do
    bodies = [
      "USER-AGENT: FooBot\nALLOW: /x/\nDISALLOW: /\n",
      "user-agent: FooBot\nallow: /x/\ndisallow: /\n",
      "uSeR-aGeNt: FooBot\nAlLoW: /x/\ndIsAlLoW: /\n"
    ]

    Enum.each(bodies, fn body ->
      assert allowed?(body, "FooBot", "http://foo.bar/x/y")
      refute allowed?(body, "FooBot", "http://foo.bar/a/b")
    end)
  end

  # ID_VerifyValidUserAgentsToObey
  test "ID_VerifyValidUserAgentsToObey" do
    Enum.each(["Foobot", "Foobot-Bar", "Foo_Bar"], &assert(RobotsTxt.valid_user_agent?(&1)))

    Enum.each(["", "ツ", "Foobot*", " Foobot ", "Foobot/2.1", "Foobot Bar"], fn value ->
      refute RobotsTxt.valid_user_agent?(value)
    end)
  end

  # ID_UserAgentValueCaseInsensitive
  test "ID_UserAgentValueCaseInsensitive" do
    bodies = [
      "User-Agent: FOO BAR\nAllow: /x/\nDisallow: /\n",
      "User-Agent: foo bar\nAllow: /x/\nDisallow: /\n",
      "User-Agent: FoO bAr\nAllow: /x/\nDisallow: /\n"
    ]

    for body <- bodies, agent <- ["Foo", "foo"] do
      assert allowed?(body, agent, "http://foo.bar/x/y")
      refute allowed?(body, agent, "http://foo.bar/a/b")
    end
  end

  # GoogleOnly_AcceptUserAgentUpToFirstSpace
  test "GoogleOnly_AcceptUserAgentUpToFirstSpace" do
    refute RobotsTxt.valid_user_agent?("Foobot Bar")

    body = "User-Agent: *\nDisallow: /\nUser-Agent: Foo Bar\nAllow: /x/\nDisallow: /\n"
    target = "http://foo.bar/x/y"

    assert allowed?(body, "Foo", target)
    refute allowed?(body, "Foo Bar", target)
  end

  # ID_GlobalGroups_Secondary
  test "ID_GlobalGroups_Secondary" do
    global = "user-agent: *\nallow: /\nuser-agent: FooBot\ndisallow: /\n"

    specific =
      "user-agent: FooBot\nallow: /\n" <>
        "user-agent: BarBot\ndisallow: /\n" <>
        "user-agent: BazBot\ndisallow: /\n"

    target = "http://foo.bar/x/y"

    assert allowed?("", "FooBot", target)
    refute allowed?(global, "FooBot", target)
    assert allowed?(global, "BarBot", target)
    assert allowed?(specific, "QuxBot", target)
  end

  # ID_AllowDisallow_Value_CaseSensitive
  test "ID_AllowDisallow_Value_CaseSensitive" do
    lower = "user-agent: FooBot\ndisallow: /x/\n"
    upper = "user-agent: FooBot\ndisallow: /X/\n"
    target = "http://foo.bar/x/y"

    refute allowed?(lower, "FooBot", target)
    assert allowed?(upper, "FooBot", target)
  end

  # ID_LongestMatch
  test "ID_LongestMatch" do
    target = "http://foo.bar/x/page.html"

    refute allowed?("user-agent: FooBot\ndisallow: /x/page.html\nallow: /x/\n", "FooBot", target)

    allow_longer = "user-agent: FooBot\nallow: /x/page.html\ndisallow: /x/\n"
    assert allowed?(allow_longer, "FooBot", target)
    refute allowed?(allow_longer, "FooBot", "http://foo.bar/x/")

    assert allowed?("user-agent: FooBot\ndisallow:\nallow:\n", "FooBot", target)
    assert allowed?("user-agent: FooBot\ndisallow: /\nallow: /\n", "FooBot", target)

    slash = "user-agent: FooBot\ndisallow: /x\nallow: /x/\n"
    refute allowed?(slash, "FooBot", "http://foo.bar/x")
    assert allowed?(slash, "FooBot", "http://foo.bar/x/")

    tie = "user-agent: FooBot\ndisallow: /x/page.html\nallow: /x/page.html\n"
    assert allowed?(tie, "FooBot", target)

    wildcard_longer = "user-agent: FooBot\nallow: /page\ndisallow: /*.html\n"
    refute allowed?(wildcard_longer, "FooBot", "http://foo.bar/page.html")
    assert allowed?(wildcard_longer, "FooBot", "http://foo.bar/page")

    literal_longer = "user-agent: FooBot\nallow: /x/page.\ndisallow: /*.html\n"
    assert allowed?(literal_longer, "FooBot", target)
    refute allowed?(literal_longer, "FooBot", "http://foo.bar/x/y.html")

    specific = "User-agent: *\nDisallow: /x/\nUser-agent: FooBot\nDisallow: /y/\n"
    assert allowed?(specific, "FooBot", "http://foo.bar/x/page")
    refute allowed?(specific, "FooBot", "http://foo.bar/y/page")
  end

  # ID_Encoding
  test "ID_Encoding" do
    query =
      "User-agent: FooBot\nDisallow: /\n" <>
        "Allow: /foo/bar?qux=taz&baz=http://foo.bar?tar&par\n"

    assert allowed?(query, "FooBot", "http://foo.bar/foo/bar?qux=taz&baz=http://foo.bar?tar&par")

    raw = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar/ツ\n"
    assert allowed?(raw, "FooBot", "http://foo.bar/foo/bar/%E3%83%84")
    refute allowed?(raw, "FooBot", "http://foo.bar/foo/bar/ツ")

    encoded = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar/%E3%83%84\n"
    assert allowed?(encoded, "FooBot", "http://foo.bar/foo/bar/%E3%83%84")
    refute allowed?(encoded, "FooBot", "http://foo.bar/foo/bar/ツ")

    unreserved = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar/%62%61%7A\n"
    refute allowed?(unreserved, "FooBot", "http://foo.bar/foo/bar/baz")
    assert allowed?(unreserved, "FooBot", "http://foo.bar/foo/bar/%62%61%7A")
  end

  # ID_SpecialCharacters
  test "ID_SpecialCharacters" do
    wildcard = "User-agent: FooBot\nDisallow: /foo/bar/quz\nAllow: /foo/*/qux\n"
    assert_disallowed(wildcard, "FooBot", ["http://foo.bar/foo/bar/quz"])

    assert_allowed(wildcard, "FooBot", [
      "http://foo.bar/foo/quz",
      "http://foo.bar/foo//quz",
      "http://foo.bar/foo/bax/quz"
    ])

    anchor = "User-agent: FooBot\nDisallow: /foo/bar$\nAllow: /foo/bar/qux\n"
    assert_disallowed(anchor, "FooBot", ["http://foo.bar/foo/bar"])

    assert_allowed(anchor, "FooBot", [
      "http://foo.bar/foo/bar/qux",
      "http://foo.bar/foo/bar/",
      "http://foo.bar/foo/bar/baz"
    ])

    comment = "User-agent: FooBot\n# Disallow: /\nDisallow: /foo/quz#qux\nAllow: /\n"
    assert allowed?(comment, "FooBot", "http://foo.bar/foo/bar")
    refute allowed?(comment, "FooBot", "http://foo.bar/foo/quz")
  end

  # GoogleOnly_IndexHTMLisDirectory
  test "GoogleOnly_IndexHTMLisDirectory" do
    body = "User-Agent: *\nAllow: /allowed-slash/index.html\nDisallow: /\n"

    assert allowed?(body, "foobot", "http://foo.com/allowed-slash/")
    refute allowed?(body, "foobot", "http://foo.com/allowed-slash/index.htm")
    assert allowed?(body, "foobot", "http://foo.com/allowed-slash/index.html")
    refute allowed?(body, "foobot", "http://foo.com/anyother-url")
  end

  # GoogleOnly_LineTooLong
  test "GoogleOnly_LineTooLong" do
    max_line_length = 2083 * 8
    prefix = "/x/"
    longline_length = max_line_length - byte_size(prefix) - byte_size("disallow: ") + 1
    longline = prefix <> String.duplicate("a", longline_length - byte_size(prefix))
    assert byte_size(longline) == longline_length
    body = "user-agent: FooBot\ndisallow: " <> longline <> "/qux\n"

    assert allowed?(body, "FooBot", "http://foo.bar/fux")
    refute allowed?(body, "FooBot", "http://foo.bar" <> longline <> "/fux")

    length = max_line_length - byte_size(prefix) - byte_size("allow: ") + 1
    longline_a = prefix <> String.duplicate("a", length - byte_size(prefix))
    longline_b = prefix <> String.duplicate("b", length - byte_size(prefix))
    assert byte_size(longline_a) == length
    assert byte_size(longline_b) == length

    body =
      "user-agent: FooBot\ndisallow: /\n" <>
        "allow: " <>
        longline_a <>
        "/qux\n" <>
        "allow: " <> longline_b <> "/qux\n"

    refute allowed?(body, "FooBot", "http://foo.bar/")
    assert allowed?(body, "FooBot", "http://foo.bar" <> longline_a <> "/qux")
    assert allowed?(body, "FooBot", "http://foo.bar" <> longline_b <> "/fux")
  end

  # GoogleOnly_DocumentationChecks
  test "GoogleOnly_DocumentationChecks path patterns" do
    fish = "user-agent: FooBot\ndisallow: /\nallow: /fish\n"

    assert_allowed(fish, "FooBot", [
      "http://foo.bar/fish",
      "http://foo.bar/fish.html",
      "http://foo.bar/fish/salmon.html",
      "http://foo.bar/fishheads",
      "http://foo.bar/fishheads/yummy.html",
      "http://foo.bar/fish.html?id=anything"
    ])

    assert_disallowed(fish, "FooBot", [
      "http://foo.bar/bar",
      "http://foo.bar/Fish.asp",
      "http://foo.bar/catfish",
      "http://foo.bar/?id=fish"
    ])

    fish_star = "user-agent: FooBot\ndisallow: /\nallow: /fish*\n"

    assert_allowed(fish_star, "FooBot", [
      "http://foo.bar/fish",
      "http://foo.bar/fish.html",
      "http://foo.bar/fish/salmon.html",
      "http://foo.bar/fishheads",
      "http://foo.bar/fishheads/yummy.html",
      "http://foo.bar/fish.html?id=anything"
    ])

    assert_disallowed(fish_star, "FooBot", [
      "http://foo.bar/bar",
      "http://foo.bar/Fish.bar",
      "http://foo.bar/catfish",
      "http://foo.bar/?id=fish"
    ])

    fish_slash = "user-agent: FooBot\ndisallow: /\nallow: /fish/\n"

    assert_allowed(fish_slash, "FooBot", [
      "http://foo.bar/fish/",
      "http://foo.bar/fish/salmon",
      "http://foo.bar/fish/?salmon",
      "http://foo.bar/fish/salmon.html",
      "http://foo.bar/fish/?id=anything"
    ])

    assert_disallowed(fish_slash, "FooBot", [
      "http://foo.bar/bar",
      "http://foo.bar/fish",
      "http://foo.bar/fish.html",
      "http://foo.bar/Fish/Salmon.html"
    ])
  end

  # GoogleOnly_DocumentationChecks
  test "GoogleOnly_DocumentationChecks wildcards and precedence" do
    php = "user-agent: FooBot\ndisallow: /\nallow: /*.php\n"

    assert_allowed(php, "FooBot", [
      "http://foo.bar/filename.php",
      "http://foo.bar/folder/filename.php",
      "http://foo.bar/folder/filename.php?parameters",
      "http://foo.bar//folder/any.php.file.html",
      "http://foo.bar/filename.php/",
      "http://foo.bar/index?f=filename.php/"
    ])

    assert_disallowed(php, "FooBot", [
      "http://foo.bar/bar",
      "http://foo.bar/php/",
      "http://foo.bar/index?php",
      "http://foo.bar/windows.PHP"
    ])

    anchored = "user-agent: FooBot\ndisallow: /\nallow: /*.php$\n"

    assert_allowed(anchored, "FooBot", [
      "http://foo.bar/filename.php",
      "http://foo.bar/folder/filename.php"
    ])

    assert_disallowed(anchored, "FooBot", [
      "http://foo.bar/bar",
      "http://foo.bar/filename.php?parameters",
      "http://foo.bar/filename.php/",
      "http://foo.bar/filename.php5",
      "http://foo.bar/php/",
      "http://foo.bar/filename?php",
      "http://foo.bar/aaaphpaaa",
      "http://foo.bar//windows.PHP"
    ])

    fish_php = "user-agent: FooBot\ndisallow: /\nallow: /fish*.php\n"

    assert_allowed(fish_php, "FooBot", [
      "http://foo.bar/fish.php",
      "http://foo.bar/fishheads/catfish.php?parameters"
    ])

    assert_disallowed(fish_php, "FooBot", ["http://foo.bar/bar", "http://foo.bar/Fish.PHP"])

    assert allowed?(
             "user-agent: FooBot\nallow: /p\ndisallow: /\n",
             "FooBot",
             "http://example.com/page"
           )

    assert allowed?(
             "user-agent: FooBot\nallow: /folder\ndisallow: /folder\n",
             "FooBot",
             "http://example.com/folder/page"
           )

    refute allowed?(
             "user-agent: FooBot\nallow: /page\ndisallow: /*.htm\n",
             "FooBot",
             "http://example.com/page.htm"
           )

    root = "user-agent: FooBot\nallow: /$\ndisallow: /\n"
    assert allowed?(root, "FooBot", "http://example.com/")
    refute allowed?(root, "FooBot", "http://example.com/page.html")
  end

  # ID_LinesNumbersAreCountedCorrectly
  test "ID_LinesNumbersAreCountedCorrectly" do
    files = [
      "User-Agent: foo\nAllow: /some/path\nUser-Agent: bar\n\n\nDisallow: /\n",
      "User-Agent: foo\r\nAllow: /some/path\r\nUser-Agent: bar\r\n\r\n\r\nDisallow: /\r\n",
      "User-Agent: foo\rAllow: /some/path\rUser-Agent: bar\r\r\rDisallow: /\r",
      "User-Agent: foo\nAllow: /some/path\nUser-Agent: bar\n\n\nDisallow: /",
      "User-Agent: foo\nAllow: /some/path\r\nUser-Agent: bar\n\r\n\nDisallow: /"
    ]

    Enum.each(files, fn body ->
      assert RobotsTxt.matched_rule(RobotsTxt.parse(body), "bar", "/") == {:disallow, "/", 6}
    end)
  end

  # ID_UTF8ByteOrderMarkIsSkipped
  test "ID_UTF8ByteOrderMarkIsSkipped" do
    suffix = "User-Agent: foo\nAllow: /AnyValue\n"

    for prefix <- [<<0xEF>>, <<0xEF, 0xBB>>, <<0xEF, 0xBB, 0xBF>>] do
      parsed = RobotsTxt.parse(prefix <> suffix)
      assert [%RobotsTxt.Group{user_agents: ["foo"]}] = parsed.groups
    end

    broken = RobotsTxt.parse(<<0xEF, 0x11, 0xBF>> <> suffix)
    assert broken.groups == []
    assert map_size(broken.global_extensions) == 1

    middle = RobotsTxt.parse("User-Agent: foo\n" <> <<0xEF, 0xBB, 0xBF>> <> "Allow: /AnyValue\n")
    assert [%RobotsTxt.Group{rules: [], extensions: extensions}] = middle.groups
    assert map_size(extensions) == 1
  end

  # ID_NonStandardLineExample_Sitemap
  test "ID_NonStandardLineExample_Sitemap" do
    location = "http://foo.bar/sitemap.xml"
    base = "User-Agent: foo\nAllow: /some/path\nUser-Agent: bar\n\n\n"

    assert RobotsTxt.sitemaps(RobotsTxt.parse(base <> "Sitemap: " <> location <> "\n")) == [
             location
           ]

    assert RobotsTxt.sitemaps(RobotsTxt.parse("Sitemap: " <> location <> "\n" <> base)) == [
             location
           ]
  end

  # TestGetPathParamsQuery
  test "TestGetPathParamsQuery" do
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

    Enum.each(cases, fn {target, expected} -> assert Matcher.path(target) == expected end)
  end

  # TestMaybeEscapePattern
  test "TestMaybeEscapePattern" do
    assert Pattern.escape("http://www.example.com") == "http://www.example.com"
    assert Pattern.escape("/a/b/c") == "/a/b/c"
    assert Pattern.escape("á") == "%C3%A1"
    assert Pattern.escape("%aa") == "%AA"
  end
end
