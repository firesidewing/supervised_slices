defmodule SupervisedSlices.MenuCache do
  @cache :menu_cache

  def fetch_customer(org_id, fun) do
    case Cachex.fetch(@cache, {org_id, :customer}, fn _ -> {:commit, fun.()} end) do
      {status, value} when status in [:ok, :commit] -> value
    end
  end

  def fetch_admin(org_id, fun) do
    case Cachex.fetch(@cache, {org_id, :admin}, fn _ -> {:commit, fun.()} end) do
      {status, value} when status in [:ok, :commit] -> value
    end
  end

  def invalidate(org_id) do
    Cachex.del(@cache, {org_id, :customer})
    Cachex.del(@cache, {org_id, :admin})
  end
end
