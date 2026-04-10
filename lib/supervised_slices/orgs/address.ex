defmodule SupervisedSlices.Orgs.Address do
  use Ash.Resource,
    data_layer: :embedded

  attributes do
    attribute :street, :string do
      allow_nil? false
      public? true
    end

    attribute :city, :string do
      allow_nil? false
      public? true
    end

    attribute :state, :string do
      allow_nil? false
      public? true
    end

    attribute :zip, :string do
      allow_nil? false
      public? true
    end

    attribute :country, :string do
      default "US"
      allow_nil? false
      public? true
    end
  end
end
