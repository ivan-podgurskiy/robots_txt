defmodule RobotsTxt.ComplianceCliTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @script Path.expand("robots_cli.exs", __DIR__)
  @beam_path Path.expand("../../_build/test/lib/robots_txt/ebin", __DIR__)

  test "exits zero when the target is allowed", %{tmp_dir: tmp_dir} do
    robots_path = Path.join(tmp_dir, "allow.txt")
    File.write!(robots_path, "User-agent: *\nDisallow: /private\n")

    {_output, status} = run_cli([robots_path, "https://example.com/public", "AnyBot"])

    assert status == 0
  end

  test "exits one when the target is disallowed", %{tmp_dir: tmp_dir} do
    robots_path = Path.join(tmp_dir, "disallow.txt")
    File.write!(robots_path, "User-agent: *\nDisallow: /private\n")

    {_output, status} = run_cli([robots_path, "https://example.com/private/page", "AnyBot"])

    assert status == 1
  end

  test "exits two and prints usage when arguments are missing" do
    {output, status} = run_cli([])

    assert status == 2
    assert output =~ "usage: elixir robots_cli.exs ROBOTS URL USER_AGENT"
  end

  defp run_cli(args) do
    System.cmd(elixir(), ["-pa", @beam_path, @script | args], stderr_to_stdout: true)
  end

  defp elixir do
    System.find_executable("elixir") || raise "elixir executable not found"
  end
end
