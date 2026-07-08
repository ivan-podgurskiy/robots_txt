usage = "usage: elixir robots_cli.exs ROBOTS URL USER_AGENT"

case System.argv() do
  [robots_path, url, user_agent] ->
    case File.read(robots_path) do
      {:ok, body} ->
        robots = RobotsTxt.parse(body)
        System.halt(if RobotsTxt.allowed?(robots, user_agent, url), do: 0, else: 1)

      {:error, reason} ->
        IO.puts(:stderr, "error: cannot read robots file: #{:file.format_error(reason)}")
        System.halt(2)
    end

  _args ->
    IO.puts(:stderr, usage)
    System.halt(2)
end
