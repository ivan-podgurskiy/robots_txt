defmodule RobotsTxt.Rule do
  @moduledoc false

  @enforce_keys [:action, :pattern, :escaped, :line]
  defstruct [:action, :pattern, :escaped, :line]

  @type t :: %__MODULE__{
          action: :allow | :disallow,
          pattern: binary(),
          escaped: binary(),
          line: pos_integer()
        }
end
