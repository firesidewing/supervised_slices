defmodule SupervisedSlices.Menu.MenuImageUploader do
  @doc """
  Resizes the image to a max 1200px dimension, converts to WebP, uploads to
  Tigris, and returns the public URL. Random suffix prevents collisions.
  """
  def upload(org_id, tmp_path, _content_type) do
    bucket = Application.fetch_env!(:supervised_slices, :tigris_bucket)
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    key = "menus/#{org_id}/#{suffix}.webp"

    resized_path = tmp_path <> ".webp"

    tmp_path
    |> Image.thumbnail!(1200, fit: :inside)
    |> Image.write!(resized_path, quality: 85)

    resized_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(bucket, key, content_type: "image/webp", acl: :public_read)
    |> ExAws.request!()

    File.rm(resized_path)

    "https://#{bucket}.fly.storage.tigris.dev/#{key}"
  end
end
