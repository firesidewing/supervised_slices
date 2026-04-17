defmodule SupervisedSlices.Orgs.LogoUploader do
  @doc """
  Resizes the logo to a max 400px dimension and converts to WebP (SVG passes
  through unchanged), uploads to Tigris, and returns the public CDN URL.
  """
  def upload(org_id, tmp_path, content_type) do
    bucket = Application.fetch_env!(:supervised_slices, :tigris_bucket)

    {key, upload_path, upload_type} =
      if content_type == "image/svg+xml" do
        {"logos/#{org_id}/logo.svg", tmp_path, "image/svg+xml"}
      else
        resized_path = tmp_path <> ".webp"

        tmp_path
        |> Image.thumbnail!(400, fit: :inside)
        |> Image.write!(resized_path, quality: 85)

        {"logos/#{org_id}/logo.webp", resized_path, "image/webp"}
      end

    upload_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(bucket, key, content_type: upload_type, acl: :public_read)
    |> ExAws.request!()

    if upload_path != tmp_path, do: File.rm(upload_path)

    "https://#{bucket}.fly.storage.tigris.dev/#{key}"
  end
end
