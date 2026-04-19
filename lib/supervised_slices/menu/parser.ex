defmodule SupervisedSlices.Menu.Parser do
  require Logger

  @model "claude-sonnet-4-6"

  def parse(file_name) do
    api_key = Application.get_env(:supervised_slices, :anthropic_api_key)

    if is_nil(api_key) || api_key == "" do
      {:error, "ANTHROPIC_API_KEY not set"}
    else
      do_parse(file_name, api_key)
    end
  end

  defp do_parse(file_name, api_key) do
    bucket = Application.fetch_env!(:supervised_slices, :tigris_bucket)

    with {:ok, %{body: body}} <-
           ExAws.S3.get_object(bucket, file_name) |> ExAws.request() do
      content_type = content_type_from_key(file_name)
      base64_image = Base.encode64(body)
      call_claude(base64_image, content_type, api_key)
    else
      {:error, reason} -> {:error, "Failed to fetch file: #{inspect(reason)}"}
    end
  end

  defp call_claude(base64_image, content_type, api_key) do
    prompt = """
    You are a menu parsing assistant. Analyze the provided menu image and extract ALL categories, menu items, sizes, and modifiers/add-ons completely.

    Return ONLY a JSON object with this exact structure. No markdown, no explanation:
    {
      "categories": [
        {
          "name": "Category Name",
          "sort_order": 0,
          "items": [
            {
              "name": "Item Name",
              "description": "Item description or null if none",
              "price": 1299,
              "sort_order": 0,
              "sizes": [
                {
                  "name": "Small",
                  "price": 999,
                  "sort_order": 0
                }
              ],
              "modifier_groups": [
                {
                  "name": "Choose a sauce",
                  "required": false,
                  "min_selections": 0,
                  "max_selections": 1,
                  "sort_order": 0,
                  "modifiers": [
                    {
                      "name": "Ranch",
                      "price_delta": 0,
                      "sort_order": 0
                    },
                    {
                      "name": "Extra Cheese",
                      "price_delta": 150,
                      "sort_order": 1
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    Rules:
    - All prices and price_delta values are integers in cents (e.g. $12.99 = 1299). Use 0 for free modifiers/add-ons.
    - If an item has sizes, set price to null and populate the sizes array. If no sizes, set sizes to [].
    - If an item has no modifier groups, set modifier_groups to [].
    - Infer required/min_selections/max_selections from context (e.g. "choose one" = required true, max_selections 1).
    - Use sort_order to preserve the visual order items appear on the menu (0-indexed).
    - Extract every modifier group visible: toppings, sauces, preparation options, add-ons, sides, etc.
    - If a modifier has no extra charge, set price_delta to 0.
    - description should be null if no description is visible.
    """

    content_block =
      cond do
        String.contains?(content_type, "pdf") ->
          %{
            type: "document",
            source: %{type: "base64", media_type: "application/pdf", data: base64_image}
          }

        String.contains?(content_type, "png") ->
          %{type: "image", source: %{type: "base64", media_type: "image/png", data: base64_image}}

        String.contains?(content_type, "gif") ->
          %{type: "image", source: %{type: "base64", media_type: "image/gif", data: base64_image}}

        String.contains?(content_type, "webp") ->
          %{
            type: "image",
            source: %{type: "base64", media_type: "image/webp", data: base64_image}
          }

        true ->
          %{
            type: "image",
            source: %{type: "base64", media_type: "image/jpeg", data: base64_image}
          }
      end

    body = %{
      model: @model,
      max_tokens: 32768,
      messages: [
        %{
          role: "user",
          content: [
            content_block,
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
           receive_timeout: 300_000
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        clean_json_decode(text)

      {:ok, %{status: status, body: body}} ->
        dbg(body)
        {:error, "Claude API error (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        dbg(reason)
        {:error, "Request to Claude failed: #{inspect(reason)}"}
    end
  end

  defp content_type_from_key(key) do
    cond do
      String.ends_with?(key, ".pdf") -> "application/pdf"
      String.ends_with?(key, ".png") -> "image/png"
      String.ends_with?(key, ".gif") -> "image/gif"
      String.ends_with?(key, ".webp") -> "image/webp"
      true -> "image/jpeg"
    end
  end

  defp clean_json_decode(text) do
    IO.inspect(text)

    case Jason.decode(text) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, _} ->
        case Regex.run(~r/\{.*\}/s, text) do
          [json_str] ->
            case Jason.decode(json_str) do
              {:ok, decoded} ->
                {:ok, decoded}

              {:error, e} ->
                dbg(e)
                {:error, "Failed to parse JSON from Claude response: #{Exception.message(e)}"}
            end

          _ ->
            {:error, "Failed to parse JSON from Claude response"}
        end
    end
  end
end
