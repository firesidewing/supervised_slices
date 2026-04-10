defmodule SupervisedSlices.Orgs.LogoUploader do
  @doc """
  Uploads a logo file to Tigris (S3-compatible) and returns the public CDN URL.

  `org_id` is used to namespace the key.
  `tmp_path` is the local temp file path from a LiveView upload entry.
  `content_type` is the MIME type of the file.
  """
  def upload(org_id, tmp_path, content_type) do
    bucket = Application.fetch_env!(:supervised_slices, :tigris_bucket)
    key = "logos/#{org_id}/logo#{ext_for(content_type)}"

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
  defp ext_for("image/svg+xml"), do: ".svg"
  defp ext_for(_), do: ""
end
