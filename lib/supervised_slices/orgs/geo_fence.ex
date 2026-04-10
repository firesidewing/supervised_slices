defmodule SupervisedSlices.Orgs.GeoFence do
  use Ash.Resource,
    data_layer: :embedded

  attributes do
    attribute :type, :atom do
      constraints one_of: [:circle, :polygon]
      default :circle
      allow_nil? false
      public? true
    end

    attribute :center_lat, :float do
      public? true
    end

    attribute :center_lng, :float do
      public? true
    end

    attribute :radius_in_km, :float do
      public? true
    end
  end
end
