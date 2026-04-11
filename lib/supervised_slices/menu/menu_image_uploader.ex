defmodule SupervisedSlices.Menu.MenuImageUploader do
  @doc """
  Uploads a menu item image to Tigris (S3-compatible) and returns the public URL.

  `org_id` namespaces the key. A random suffix prevents collisions and allows
  easy cache busting when an image is replaced.
  """
  def upload(org_id, tmp_path, content_type) do
    bucket = Application.fetch_env!(:supervised_slices, :tigris_bucket)
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    key = "menus/#{org_id}/#{suffix}#{ext_for(content_type)}"

    tmp_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(bucket, key, content_type: content_type, acl: :public_read)
    |> ExAws.request!()

    "https://#{bucket}.fly.storage.tigris.dev/#{key}"
  end

  defp ext_for("image/png"), do: ".png"
  defp ext_for("image/jpeg"), do: ".jpg"
  defp ext_for("image/gif"), do: ".gif"
  defp ext_for("image/webp"), do: ".webp"
  defp ext_for(_), do: ""
end
