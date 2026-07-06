defmodule RobotsTxt.Group do
  @moduledoc false

  alias RobotsTxt.Rule

  defstruct user_agents: [], rules: [], crawl_delays: [], extensions: %{}

  @type t :: %__MODULE__{
          user_agents: [binary()],
          rules: [Rule.t()],
          crawl_delays: [binary()],
          extensions: %{optional(binary()) => [binary()]}
        }
end
