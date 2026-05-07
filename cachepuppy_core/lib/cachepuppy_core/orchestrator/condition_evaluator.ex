defmodule CachePuppyCore.Orchestrator.ConditionEvaluator do
  @moduledoc false

  @operators ["<=", ">=", "==", "!=", "<", ">"]
  @regex ~r/^\s*([a-zA-Z_][\w\.]*)\s*(<=|>=|==|!=|<|>)\s*(.+?)\s*$/

  @spec evaluate(String.t(), map()) :: {:ok, boolean()} | {:error, :invalid_expression}
  def evaluate(expr, output) when is_binary(expr) and is_map(output) do
    with [_, left_path, op, right_raw] <- Regex.run(@regex, expr),
         {:ok, left} <- resolve_path(left_path, %{"result" => output}),
         {:ok, right} <- parse_literal(right_raw),
         true <- op in @operators do
      {:ok, compare(left, right, op)}
    else
      _ -> {:error, :invalid_expression}
    end
  end

  def evaluate(_, _), do: {:error, :invalid_expression}

  defp resolve_path(path, data) do
    value =
      path
      |> String.split(".")
      |> Enum.reduce_while(data, fn segment, acc ->
        case acc do
          %{} = m ->
            cond do
              Map.has_key?(m, segment) ->
                {:cont, Map.get(m, segment)}

              Map.has_key?(m, String.to_atom(segment)) ->
                {:cont, Map.get(m, String.to_atom(segment))}

              true ->
                {:halt, :missing}
            end

          _ ->
            {:halt, :missing}
        end
      end)

    case value do
      :missing -> {:error, :invalid_expression}
      other -> {:ok, other}
    end
  rescue
    ArgumentError -> {:error, :invalid_expression}
  end

  defp parse_literal(raw) do
    trimmed = String.trim(raw)

    cond do
      String.starts_with?(trimmed, "\"") and String.ends_with?(trimmed, "\"") ->
        {:ok, String.slice(trimmed, 1..-2//1)}

      String.starts_with?(trimmed, "'") and String.ends_with?(trimmed, "'") ->
        {:ok, String.slice(trimmed, 1..-2//1)}

      trimmed == "true" ->
        {:ok, true}

      trimmed == "false" ->
        {:ok, false}

      Regex.match?(~r/^-?\d+\.\d+$/, trimmed) ->
        case Float.parse(trimmed) do
          {f, ""} -> {:ok, f}
          _ -> {:error, :invalid_expression}
        end

      Regex.match?(~r/^-?\d+$/, trimmed) ->
        case Integer.parse(trimmed) do
          {i, ""} -> {:ok, i}
          _ -> {:error, :invalid_expression}
        end

      true ->
        {:error, :invalid_expression}
    end
  end

  defp compare(left, right, "<"), do: left < right
  defp compare(left, right, ">"), do: left > right
  defp compare(left, right, "<="), do: left <= right
  defp compare(left, right, ">="), do: left >= right
  defp compare(left, right, "=="), do: left == right
  defp compare(left, right, "!="), do: left != right
end
