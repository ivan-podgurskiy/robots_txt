defmodule RobotsTxt.PatternTest do
  use ExUnit.Case, async: true

  alias RobotsTxt.Pattern

  test "escape/1 normalizes escapes and non-ASCII bytes without decoding" do
    assert Pattern.escape("/a%2f") == "/a%2F"
    assert Pattern.escape(<<"/caf", 0xC3, 0xA9>>) == "/caf%C3%A9"
    assert Pattern.escape("/%2F") == "/%2F"
    assert Pattern.escape("/%zz") == "/%zz"
  end

  test "match?/2 implements prefix matching" do
    assert Pattern.match?("/private/x", "/private/")
    refute Pattern.match?("/public/x", "/private/")
    assert Pattern.match?("anything", "")
  end

  test "match?/2 implements wildcard matching" do
    assert Pattern.match?("/a/x/b", "/a/*/b")
    assert Pattern.match?("/a/x/y/b", "/a/*/b")
    refute Pattern.match?("/a/x/c", "/a/*/b")
  end

  test "match?/2 treats only a final dollar as an anchor" do
    assert Pattern.match?("/exact", "/exact$")
    refute Pattern.match?("/exact/more", "/exact$")
    assert Pattern.match?("/cash$money", "/cash$money")
  end
end
