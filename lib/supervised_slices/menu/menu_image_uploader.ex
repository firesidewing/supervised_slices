defmodule SupervisedSlices.Menu.MenuImageUploader do
  def upload(org_id, tmp_path, "application/pdf") do
    bucket = Application.fetch_env!(:supervised_slices, :tigris_bucket)
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    key = "menus/#{org_id}/#{suffix}.pdf"

    tmp_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(bucket, key, content_type: "application/pdf", acl: :public_read)
    |> ExAws.request!()

    key
  end

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

    key
  end
end
