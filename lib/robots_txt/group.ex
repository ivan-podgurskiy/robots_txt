defmodule RobotsTxt.Group do
  @moduledoc """
  Parsed representation of one robots.txt user-agent group.

  A group contains consecutive user-agent declarations and the directives that
  apply to them. Values remain in file order so matching and inspection can
  reproduce source precedence.

  This module is an implementation detail. Its fields may change before
  version 1.0; use functions on `RobotsTxt` for application behavior.
  """

  alias RobotsTxt.Rule

  defstruct user_agents: [], rules: [], crawl_delays: [], extensions: %{}

  @typedoc """
  An inspectable parsed group.

  `rules` contains allow and disallow rules, `crawl_delays` retains raw values,
  and `extensions` maps lowercased directive names to values in file order.
  """
  @type t :: %__MODULE__{
          user_agents: [binary()],
          rules: [Rule.t()],
          crawl_delays: [binary()],
          extensions: %{optional(binary()) => [binary()]}
        }
end
