defmodule Bamboo.SendcloudAdapter do
  @moduledoc """
  Sends email using Sendcloud’s API.

  Use this adapter to send emails through Sendcloud’s API.
  Requires an API user and an API key are set in the config.

  ## Example config

      # In config/config.exs, or config.prod.exs, etc.
      config :my_app, MyApp.Mailer,
        adapter: Bamboo.SendcloudAdapter,
        api_user: "my_api_user",
        api_key: "my_api_key"

      # Define a Mailer. Maybe in lib/my_app/mailer.ex
      defmodule MyApp.Mailer do
        use Bamboo.Mailer, otp_app: :my_app
      end
  """
  @behaviour Bamboo.Adapter

  @base_uri "http://api.sendcloud.net/apiv2"
  @base_uri_international "http://api2.sendcloud.net/api"
  @send_email_path "/mail/send"
  @send_template_email_path "/mail/sendtemplate"

  alias Bamboo.Email
  alias Bamboo.SendcloudAdapter.{ApiError, Config}

  def deliver(email, config) when is_map(config) do
    config = Config.from_map(config)
    body = email |> to_sendcloud_body()
    uri = api_uri(email, config)

    {:ok, json} = do_request(uri, body, config)

    case json do
      %{"info" => info, "message" => _, "result" => true, "statusCode" => 200} ->
        {:ok, info}

      %{"message" => msg, "result" => false, "statusCode" => code} ->
        raise(ApiError, {:sendcloud, %{message: msg, code: code}})
    end
  end

  defp do_request(uri, body, config) do
    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    encoded_body =
      body
      |> append_auth_info(config)
      |> Plug.Conn.Query.encode()

    with {:ok, 200, _headers, response} <-
           :hackney.post(uri, headers, encoded_body, [:with_body]),
         {:ok, json} <- Jason.decode(response) do
      {:ok, json}
    else
      {:error, %Jason.DecodeError{}} ->
        raise(ApiError, :json)

      {:ok, _status, _headers, response} ->
        raise(ApiError, {:http, %{req_body: body, response: response}})

      {:error, reason} ->
        raise(ApiError, {:plain, %{message: inspect(reason)}})
    end
  end

  @doc false
  def handle_config(config) do
    for setting <- [:api_user, :api_key] do
      if config[setting] in [nil, ""] do
        raise_missing_setting_error(config, setting)
      end
    end

    config
  end

  @doc false
  def supports_attachments?, do: false

  defp raise_missing_setting_error(config, setting) do
    raise ArgumentError, """
    There was no #{setting} set for the Sendcloud adapter.

    Here are the config options that were passed in:

    #{inspect(config)}
    """
  end

  defp append_auth_info(body, config) do
    body
    |> Keyword.put(:apiUser, config.api_user)
    |> Keyword.put(:apiKey, config.api_key)
  end

  defp to_sendcloud_body(%Email{private: %{template_name: _, sub: _}} = email) do
    # send template email
    email
    |> Map.from_struct()
    |> put_from(email)
    |> put_to(email)
    |> put_headers(email)
    |> put_template_name(email)
    |> put_xsmtpapi(email)
    |> filter_non_empty_sendcloud_fields()
  end

  defp to_sendcloud_body(%Email{} = email) do
    # send standard email
    email
    |> Map.from_struct()
    |> put_from(email)
    |> put_to(email)
    |> put_cc(email)
    |> put_bcc(email)
    |> put_html_body(email)
    |> put_text_body(email)
    |> put_headers(email)
    |> filter_non_empty_sendcloud_fields()
  end

  defp put_from(body, %Email{from: from}) do
    email =
      case from do
        {nil, email} -> email
        {name, email} -> "#{name}<#{email}>"
      end

    body
    |> Map.put(:from, email)
  end

  defp put_to(body, %Email{to: to}) do
    email = do_transform_email(to)

    body
    |> Map.put(:to, email)
  end

  defp put_cc(body, %Email{cc: cc}) do
    email = do_transform_email(cc)

    body
    |> Map.put(:cc, email)
  end

  defp put_bcc(body, %Email{bcc: bcc}) do
    email = do_transform_email(bcc)

    body
    |> Map.put(:bcc, email)
  end

  defp do_transform_email(list) when is_list(list) do
    list
    |> Enum.map(&do_transform_email/1)
    |> Enum.join(";")
  end

  defp do_transform_email({_name, email}) do
    # Sendcloud does not allow name in email address.
    email
  end

  defp put_html_body(body, %Email{html_body: html_body}), do: Map.put(body, :html, html_body)

  defp put_text_body(body, %Email{text_body: text_body}), do: Map.put(body, :plain, text_body)

  defp put_headers(body, %Email{headers: headers}) do
    encoded =
      headers
      |> Jason.encode!()

    Map.put(body, :headers, encoded)
  end

  defp put_template_name(body, %Email{private: %{template_name: tpl_name, sub: _}}) do
    body
    |> Map.put(:templateInvokeName, tpl_name)
  end

  defp put_xsmtpapi(%{to: to} = body, %Email{private: %{template_name: _, sub: %{} = sub}}) do
    content =
      %{
        to: [to],
        sub: sub
      }
      |> Jason.encode!()

    body
    |> Map.put(:xsmtpapi, content)
  end

  defp base_uri(%Config{api_type: :china_mainland}, path) do
    @base_uri <> path
  end

  defp base_uri(_config, path) do
    @base_uri_international <> path
  end

  defp api_uri(%Email{private: %{template_name: _, sub: _}}, config) do
    base_uri(config, @send_template_email_path)
  end

  defp api_uri(%Email{}, config) do
    base_uri(config, @send_email_path)
  end

  @sendcloud_message_fields ~w(from to cc bcc subject plain html headers templateInvokeName xsmtpapi)a

  defp filter_non_empty_sendcloud_fields(map) do
    Enum.filter(map, fn {key, value} ->
      key in @sendcloud_message_fields && !(value in [nil, "", []])
    end)
  end
end
