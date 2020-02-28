defmodule Bamboo.SendcloudAdapter.Config do
  defstruct api_user: nil, api_key: nil, api_type: :china_mainland

  def from_map(config) when is_map(config) do
    api_user = config |> Map.get(:api_user)
    api_key = config |> Map.get(:api_key)
    api_type = config |> Map.get(:api_type, :china_mainland)

    %Bamboo.SendcloudAdapter.Config{
      api_user: api_user,
      api_key: api_key,
      api_type: api_type
    }
  end
end
