defmodule RobotsTxt.Matcher do
  @moduledoc """
  Selects robots.txt groups and evaluates rules against escaped targets.

  The matcher reproduces Google's specific/global precedence and four-slot
  accumulation model. This module is an implementation detail; applications
  should call `RobotsTxt.allowed?/3` or `RobotsTxt.matched_rule/3`.
  """

  alias RobotsTxt.Group
  alias RobotsTxt.Pattern
  alias RobotsTxt.Rule

  @doc """
  Returns the path, parameters, and query portion of a target.

  Scheme, authority, and fragment are removed. The result always begins with
  `/`, and malformed or pathless targets fall back to `/`.
  """
  @spec path(binary()) :: binary()
  def path(target) when is_binary(target) do
    search_start = if starts_with_double_slash?(target), do: 2, else: 0
    early_path = find_from(target, ["/", "?", ";"], search_start)
    protocol = find_from(target, "://", search_start)

    path_start =
      find_from(target, ["/", "?", ";"], authority_end(early_path, protocol, search_start))

    extract_path(target, path_start, find_from(target, "#", search_start))
  end

  @doc """
  Returns the rule that decides a target, or `:default` when no rule decides.
  """
  @spec matched_rule(RobotsTxt.t(), binary(), binary()) ::
          {:allow | :disallow, binary(), pos_integer()} | :default
  def matched_rule(%RobotsTxt{} = robots, user_agent, target)
      when is_binary(user_agent) and is_binary(target) do
    target_path = path(target)

    slots =
      Enum.reduce(robots.groups, empty_slots(), fn group, slots ->
        accumulate_group(slots, group, user_agent, target_path)
      end)

    slots
    |> winning_match()
    |> match_result()
  end

  @doc """
  Returns the groups selected for non-standard metadata accessors.

  All matching specific groups are returned when any exist; otherwise all
  matching global groups are returned. File order is preserved.
  """
  @spec selected_groups(RobotsTxt.t(), binary()) :: [Group.t()]
  def selected_groups(%RobotsTxt{} = robots, user_agent) when is_binary(user_agent) do
    {specific, global} =
      Enum.reduce(robots.groups, {[], []}, fn group, {specific, global} ->
        case group_kind(group, user_agent) do
          :specific -> {[group | specific], global}
          :global -> {specific, [group | global]}
          :none -> {specific, global}
        end
      end)

    case specific do
      [] -> Enum.reverse(global)
      _groups -> Enum.reverse(specific)
    end
  end

  defp empty_slots do
    %{
      specific_seen: false,
      specific_allow: nil,
      specific_disallow: nil,
      global_allow: nil,
      global_disallow: nil
    }
  end

  defp accumulate_group(slots, group, user_agent, target_path) do
    case group_kind(group, user_agent) do
      :specific ->
        group.rules
        |> Enum.reduce(
          %{slots | specific_seen: true},
          &accumulate_rule(&2, &1, :specific, target_path)
        )

      :global ->
        Enum.reduce(group.rules, slots, &accumulate_rule(&2, &1, :global, target_path))

      :none ->
        slots
    end
  end

  defp accumulate_rule(slots, rule, scope, target_path) do
    case rule_priority(rule, target_path) do
      nil -> slots
      priority -> update_slot(slots, scope, rule.action, priority, rule)
    end
  end

  defp rule_priority(%Rule{action: :allow, escaped: pattern}, target_path) do
    if Pattern.match?(target_path, pattern) do
      byte_size(pattern)
    else
      index_directory_priority(pattern, target_path)
    end
  end

  defp rule_priority(%Rule{escaped: pattern}, target_path) do
    if Pattern.match?(target_path, pattern), do: byte_size(pattern)
  end

  defp rule_priority(_rule, _target_path), do: nil

  defp index_directory_priority(pattern, target_path) do
    case last_slash(pattern) do
      nil ->
        nil

      slash_position ->
        suffix = binary_part(pattern, slash_position, byte_size(pattern) - slash_position)
        retry_index_directory(pattern, target_path, slash_position, suffix)
    end
  end

  defp retry_index_directory(
         pattern,
         target_path,
         slash_position,
         <<"/index.htm", _rest::binary>>
       ) do
    retry = binary_part(pattern, 0, slash_position + 1) <> "$"
    if Pattern.match?(target_path, retry), do: byte_size(retry)
  end

  defp retry_index_directory(_pattern, _target_path, _slash_position, _suffix), do: nil

  defp last_slash(pattern) do
    case :binary.matches(pattern, "/") do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end

  defp update_slot(slots, scope, action, priority, rule) do
    slot = slot_name(scope, action)

    case Map.fetch!(slots, slot) do
      nil ->
        Map.put(slots, slot, %{priority: priority, rule: rule})

      %{priority: current} when current < priority ->
        Map.put(slots, slot, %{priority: priority, rule: rule})

      _match ->
        slots
    end
  end

  defp slot_name(:specific, :allow), do: :specific_allow
  defp slot_name(:specific, :disallow), do: :specific_disallow
  defp slot_name(:global, :allow), do: :global_allow
  defp slot_name(:global, :disallow), do: :global_disallow

  defp winning_match(slots) do
    cond do
      positive?(slots.specific_allow) or positive?(slots.specific_disallow) ->
        higher_priority(slots.specific_allow, slots.specific_disallow)

      slots.specific_seen ->
        nil

      positive?(slots.global_allow) or positive?(slots.global_disallow) ->
        higher_priority(slots.global_allow, slots.global_disallow)

      true ->
        nil
    end
  end

  defp positive?(%{priority: priority}), do: priority > 0
  defp positive?(nil), do: false

  defp higher_priority(nil, disallow), do: disallow
  defp higher_priority(allow, nil), do: allow

  defp higher_priority(
         %{priority: allow_priority} = allow,
         %{priority: disallow_priority} = disallow
       ) do
    if disallow_priority > allow_priority, do: disallow, else: allow
  end

  defp match_result(nil), do: :default

  defp match_result(%{rule: %Rule{action: action, pattern: pattern, line: line}}) do
    {action, pattern, line}
  end

  defp group_kind(%Group{user_agents: user_agents}, user_agent) do
    {specific?, global?} =
      Enum.reduce(user_agents, {false, false}, fn file_agent, {specific?, global?} ->
        {specific? or specific_agent?(file_agent, user_agent),
         global? or global_agent?(file_agent)}
      end)

    cond do
      specific? -> :specific
      global? -> :global
      true -> :none
    end
  end

  defp specific_agent?(file_agent, user_agent) do
    file_agent
    |> extract_user_agent()
    |> ascii_equal?(user_agent)
  end

  defp extract_user_agent(value) do
    binary_part(value, 0, user_agent_length(value, 0))
  end

  defp user_agent_length(<<char, rest::binary>>, length)
       when char in ?A..?Z or char in ?a..?z or char in [?-, ?_] do
    user_agent_length(rest, length + 1)
  end

  defp user_agent_length(_rest, length), do: length

  defp ascii_equal?(left, right) when byte_size(left) != byte_size(right), do: false
  defp ascii_equal?(<<>>, <<>>), do: true

  defp ascii_equal?(<<left, left_rest::binary>>, <<right, right_rest::binary>>) do
    ascii_downcase(left) == ascii_downcase(right) and ascii_equal?(left_rest, right_rest)
  end

  defp ascii_downcase(char) when char in ?A..?Z, do: char + 32
  defp ascii_downcase(char), do: char

  defp global_agent?(<<"*">>), do: true

  defp global_agent?(<<"*", whitespace, _rest::binary>>)
       when whitespace in [9, 10, 11, 12, 13, 32],
       do: true

  defp global_agent?(_value), do: false

  defp starts_with_double_slash?(<<"//", _rest::binary>>), do: true
  defp starts_with_double_slash?(_target), do: false

  defp authority_end(early_path, protocol, search_start) do
    if protocol_marker?(early_path, protocol), do: protocol + 3, else: search_start
  end

  defp protocol_marker?(nil, protocol), do: not is_nil(protocol)
  defp protocol_marker?(_early_path, nil), do: false
  defp protocol_marker?(early_path, protocol), do: protocol <= early_path

  defp extract_path(_target, nil, _fragment), do: "/"

  defp extract_path(_target, path_start, fragment)
       when not is_nil(fragment) and fragment < path_start,
       do: "/"

  defp extract_path(target, path_start, fragment) do
    path_end = fragment || byte_size(target)
    result = binary_part(target, path_start, path_end - path_start)
    if :binary.at(target, path_start) == ?/, do: result, else: "/" <> result
  end

  defp find_from(value, _pattern, start) when start >= byte_size(value), do: nil

  defp find_from(value, pattern, start) do
    case :binary.match(value, pattern, scope: {start, byte_size(value) - start}) do
      {position, _length} -> position
      :nomatch -> nil
    end
  end
end
