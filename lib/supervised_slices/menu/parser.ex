defmodule SupervisedSlices.Menu.Parser do
  require Logger

  @model "claude-sonnet-4-6"

  def parse(file_url) do
    api_key = Application.get_env(:supervised_slices, :anthropic_api_key)

    if is_nil(api_key) || api_key == "" do
      {:error, "ANTHROPIC_API_KEY not set"}
    else
      do_parse(file_url, api_key)
    end
  end

  defp do_parse(file_url, api_key) do
    case Req.get(file_url) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        content_type =
          case List.keyfind(headers, "content-type", 0) do
            {"content-type", ct} -> ct
            _ -> "image/jpeg"
          end

        base64_image = Base.encode64(body)
        call_claude(base64_image, content_type, api_key)

      {:ok, %{status: status}} ->
        {:error, "Failed to fetch image: status #{status}"}

      {:error, reason} ->
        {:error, "Failed to fetch image: #{inspect(reason)}"}
    end
  end

  defp call_claude(base64_image, content_type, api_key) do
    prompt = """
    You are a menu parsing assistant. Analyze the provided menu image and extract the categories and menu items.
    Return the result as a JSON object with the following structure:
    {
      "categories": [
        {
          "name": "Category Name",
          "items": [
            {
              "name": "Item Name",
              "description": "Item Description",
              "price": 1299 // price in cents as an integer. If no price is found, use null.
            }
          ]
        }
      ]
    }
    Only return the JSON object, nothing else. Do not include any markdown formatting like ```json.
    """

    # Anthropic expects specific media types: image/jpeg, image/png, image/gif, image/webp
    media_type =
      cond do
        String.contains?(content_type, "png") -> "image/png"
        String.contains?(content_type, "gif") -> "image/gif"
        String.contains?(content_type, "webp") -> "image/webp"
        true -> "image/jpeg"
      end

    body = %{
      model: @model,
      max_tokens: 4096,
      messages: [
        %{
          role: "user",
          content: [
            %{
              type: "image",
              source: %{
                type: "base64",
                media_type: media_type,
                data: base64_image
              }
            },
            %{
              type: "text",
              text: prompt
            }
          ]
        }
      ]
    }

    case Req.post("https://api.anthropic.com/v1/messages",
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"}
           ],
           # Set a long timeout for LLM
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        clean_json_decode(text)

      {:ok, %{status: status, body: body}} ->
        {:error, "Claude API error (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request to Claude failed: #{inspect(reason)}"}
    end
  end

  defp clean_json_decode(text) do
    case Jason.decode(text) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, _} ->
        case Regex.run(~r/\{.*\}/s, text) do
          [json_str] -> Jason.decode(json_str)
          _ -> {:error, "Failed to parse JSON from Claude response"}
        end
    end
  end
end
