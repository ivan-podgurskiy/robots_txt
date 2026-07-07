defmodule RobotsTxt.Rule do
  @moduledoc """
  Parsed representation of an allow or disallow rule.

  The original pattern is retained for inspection and matched-rule reporting;
  the escaped pattern is the canonical byte sequence used by the matcher. The
  one-based source line identifies where the decision originated.

  This module is an implementation detail and is not a stable public API before
  version 1.0.
  """

  @enforce_keys [:action, :pattern, :escaped, :line]
  defstruct [:action, :pattern, :escaped, :line]

  @typedoc """
  A parsed robots.txt access rule.

  `action` is either `:allow` or `:disallow`. `pattern` is source-facing,
  whereas `escaped` is normalized for byte-oriented matching.
  """
  @type t :: %__MODULE__{
          action: :allow | :disallow,
          pattern: binary(),
          escaped: binary(),
          line: pos_integer()
        }
end
