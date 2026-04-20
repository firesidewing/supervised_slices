defmodule SupervisedSlices.Menu.Parser.ParsedModifier do
  defstruct [:name, :price_delta, :sort_order, size_price_overrides: %{}]
end

defmodule SupervisedSlices.Menu.Parser.ParsedModifierGroup do
  defstruct [:name, :required, :min_selections, :max_selections, :sort_order, modifiers: []]
end

defmodule SupervisedSlices.Menu.Parser.ParsedSize do
  defstruct [:name, :price, :sort_order]
end

defmodule SupervisedSlices.Menu.Parser.ParsedItem do
  defstruct [:name, :description, :price, :sort_order, sizes: [], modifier_group_names: []]
end

defmodule SupervisedSlices.Menu.Parser.ParsedCategory do
  defstruct [:name, :sort_order, items: []]
end

defmodule SupervisedSlices.Menu.Parser.ParsedMenu do
  defstruct modifier_groups: [], categories: []
end

defmodule SupervisedSlices.Menu.Parser do
  require Logger

  alias SupervisedSlices.Menu.Parser.{
    ParsedMenu,
    ParsedCategory,
    ParsedItem,
    ParsedSize,
    ParsedModifierGroup,
    ParsedModifier
  }

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
              "sort_order": 0,
              "size_price_overrides": {}
            },
            {
              "name": "Extra Cheese",
              "price_delta": 150,
              "sort_order": 1,
              "size_price_overrides": {
                "10\"": 100,
                "12\"": 150,
                "14\"": 200
              }
            }
          ]
        }
      ],
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
              "modifier_group_names": ["Choose a sauce"]
            }
          ]
        }
      ]
    }

    Rules:
    - All prices, price_delta, and size_price_overrides values are integers in cents (e.g. $12.99 = 1299). Use 0 for free modifiers/add-ons.
    - If an item has sizes, set price to null and populate the sizes array. If no sizes, set sizes to [].
    - Collect ALL modifier groups at the top level in the "modifier_groups" array. Do not embed modifier groups inside items.
    - Each item's "modifier_group_names" is a list of modifier group name strings referencing top-level modifier groups that apply to that item.
    - If an item has no modifier groups, set modifier_group_names to [].
    - Infer required/min_selections/max_selections from context (e.g. "choose one" = required true, max_selections 1). If there is no maximum (customers can select any number of options), set max_selections to null.
    - Use sort_order to preserve the visual order items appear on the menu (0-indexed).
    - Extract every modifier group visible: toppings, sauces, preparation options, add-ons, sides, etc.
    - If a modifier has no extra charge, set price_delta to 0.
    - description should be null if no description is visible.
    - For size_price_overrides: if a modifier costs different amounts depending on item size (e.g. extra cheese is $1.00 on a 10" but $1.50 on a 12"), populate size_price_overrides with the size name as key and price in cents as value. The size names must exactly match the sizes defined in the item's sizes array. If the price is the same for all sizes, leave size_price_overrides as {}.
    - Only add size_price_overrides entries for sizes where the price differs from the default price_delta.
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
        save_debug_output(text)

        case clean_json_decode(text) do
          {:ok, decoded} -> {:ok, decode_to_structs(decoded)}
          error -> error
        end

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

  defp save_debug_output(text) do
    path = "/tmp/menu_parse_#{System.os_time(:second)}.json"

    case File.write(path, text) do
      :ok ->
        Logger.info("Menu parse debug output saved to #{path}")

      {:error, reason} ->
        Logger.warning("Failed to save menu parse debug output: #{inspect(reason)}")
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

  defp normalize_max_selections(nil), do: nil
  defp normalize_max_selections(0), do: nil
  defp normalize_max_selections(n) when is_integer(n) and n >= 99, do: nil
  defp normalize_max_selections(n) when is_integer(n), do: n
  defp normalize_max_selections(_), do: nil

  defp cents_to_decimal(nil), do: nil
  defp cents_to_decimal(cents) when is_integer(cents), do: Decimal.div(Decimal.new(cents), 100)
  defp cents_to_decimal(_), do: nil

  defp decode_to_structs(raw) do
    modifier_groups =
      (raw["modifier_groups"] || [])
      |> Enum.map(fn g ->
        modifiers =
          (g["modifiers"] || [])
          |> Enum.map(fn m ->
            size_price_overrides =
              (m["size_price_overrides"] || %{})
              |> Map.new(fn {size_name, cents} ->
                {size_name, cents_to_decimal(cents)}
              end)
              |> Map.reject(fn {_k, v} -> is_nil(v) end)

            %ParsedModifier{
              name: m["name"],
              price_delta: cents_to_decimal(m["price_delta"]),
              sort_order: m["sort_order"] || 0,
              size_price_overrides: size_price_overrides
            }
          end)

        %ParsedModifierGroup{
          name: g["name"],
          required: g["required"] || false,
          min_selections: g["min_selections"] || 0,
          max_selections: normalize_max_selections(g["max_selections"]),
          sort_order: g["sort_order"] || 0,
          modifiers: modifiers
        }
      end)

    categories =
      (raw["categories"] || [])
      |> Enum.map(fn c ->
        items =
          (c["items"] || [])
          |> Enum.map(fn i ->
            sizes =
              (i["sizes"] || [])
              |> Enum.map(fn s ->
                %ParsedSize{
                  name: s["name"],
                  price: cents_to_decimal(s["price"]),
                  sort_order: s["sort_order"] || 0
                }
              end)

            %ParsedItem{
              name: i["name"],
              description: i["description"],
              price: cents_to_decimal(i["price"]),
              sort_order: i["sort_order"] || 0,
              sizes: sizes,
              modifier_group_names: i["modifier_group_names"] || []
            }
          end)

        %ParsedCategory{
          name: c["name"],
          sort_order: c["sort_order"] || 0,
          items: items
        }
      end)

    %ParsedMenu{modifier_groups: modifier_groups, categories: categories}
  end
end
