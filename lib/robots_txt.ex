defmodule RobotsTxt do
  @moduledoc """
  Parses robots.txt files and answers whether a crawler may fetch a target.

  This module contains the complete public API. Parsing and matching are pure;
  fetching, caching, and crawler scheduling remain the caller's responsibility.
  """

  alias RobotsTxt.Group

  defstruct groups: [], sitemaps: [], global_extensions: %{}

  @type t :: %__MODULE__{
          groups: [Group.t()],
          sitemaps: [binary()],
          global_extensions: %{optional(binary()) => [binary()]}
        }

  @doc """
  Classifies a final HTTP response according to RFC 9309 fetch semantics.

  Informational and redirect responses are intentionally outside the function's
  domain because callers must follow redirects before classifying the result.
  """
  @spec fetch_semantics(200..299 | 400..499 | 500..599) ::
          :parse_body | :allow_all | :disallow_all
  def fetch_semantics(status) when status in 200..299, do: :parse_body
  def fetch_semantics(status) when status in 400..499, do: :allow_all
  def fetch_semantics(status) when status in 500..599, do: :disallow_all

  @doc """
  Returns whether a crawler product token can match a specific robots group.

  Valid tokens are non-empty and contain only ASCII letters, `-`, and `_`.
  """
  @spec valid_user_agent?(term()) :: boolean()
  def valid_user_agent?(value) when is_binary(value) and byte_size(value) > 0 do
    valid_user_agent_bytes?(value)
  end

  def valid_user_agent?(_value), do: false

  defp valid_user_agent_bytes?(<<>>), do: true

  defp valid_user_agent_bytes?(<<char, rest::binary>>)
       when char in ?A..?Z or char in ?a..?z or char in [?-, ?_] do
    valid_user_agent_bytes?(rest)
  end

  defp valid_user_agent_bytes?(_value), do: false
end
