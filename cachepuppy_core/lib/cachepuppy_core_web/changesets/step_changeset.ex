defmodule CachePuppyCoreWeb.Changesets.StepChangeset do
  @moduledoc false

  import Ecto.Changeset

  @types %{
    step_name: :string,
    url: :string,
    method: :string,
    data: :map,
    success_codes: {:array, :integer},
    max_retries: :integer,
    step_id: :string,
    parent_ids: {:array, :string}
  }

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(params) when is_map(params) do
    attrs = normalize(params)

    {%{}, @types}
    |> cast(attrs, Map.keys(@types))
    |> apply_common_validations()
  end

  @spec apply_common_validations(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def apply_common_validations(changeset) do
    changeset
    |> validate_required([:step_name, :url, :method])
    |> validate_length(:step_name, max: 100)
    |> validate_length(:url, min: 8)
    |> validate_change(:url, fn :url, v ->
      if String.starts_with?(v, "http://") or String.starts_with?(v, "https://"),
        do: [],
        else: [url: "must start with http:// or https://"]
    end)
    |> update_change(:method, &String.downcase/1)
    |> validate_inclusion(:method, ~w(get post put patch delete))
    |> put_default(:data, %{})
    |> put_default(:success_codes, [200])
    |> validate_change(:success_codes, fn :success_codes, list ->
      if is_list(list) and Enum.all?(list, &is_integer/1),
        do: [],
        else: [success_codes: "must be a list of integers"]
    end)
    |> put_default(:max_retries, 3)
    |> validate_number(:max_retries, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> maybe_validate_parent_ids()
  end

  defp maybe_validate_parent_ids(changeset) do
    if Map.has_key?(changeset.types, :parent_ids) do
      validate_change(changeset, :parent_ids, fn :parent_ids, list ->
        if is_list(list) and Enum.all?(list, &is_binary/1),
          do: [],
          else: [parent_ids: "must be a list of strings"]
      end)
    else
      changeset
    end
  end

  @spec validate_params(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def validate_params(params) when is_map(params) do
    cs = changeset(params)

    if cs.valid? do
      {:ok, apply_changes(cs)}
    else
      {:error, cs}
    end
  end

  @spec to_step_params(map(), String.t() | nil) :: map()
  def to_step_params(validated, step_id \\ nil) do
    resolved_step_id = step_id || Map.get(validated, :step_id)

    base = %{
      step_name: validated.step_name,
      url: validated.url,
      method: String.upcase(validated.method),
      data: validated.data || %{},
      success_codes: validated.success_codes || [200],
      max_retries: validated.max_retries || 3,
      parent_ids: Map.get(validated, :parent_ids, []) || []
    }

    case resolved_step_id do
      nil -> base
      id -> Map.put(base, :step_id, id)
    end
  end

  defp put_default(changeset, key, value) do
    if get_field(changeset, key) == nil do
      put_change(changeset, key, value)
    else
      changeset
    end
  end

  defp normalize(params) do
    %{
      step_name: Map.get(params, "stepName"),
      url: Map.get(params, "url"),
      method: Map.get(params, "method"),
      data: Map.get(params, "data"),
      success_codes: Map.get(params, "successCodes"),
      max_retries: Map.get(params, "maxRetries"),
      step_id: Map.get(params, "stepId"),
      parent_ids: Map.get(params, "parentIds")
    }
  end
end
