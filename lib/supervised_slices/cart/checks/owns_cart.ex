defmodule SupervisedSlices.Cart.Checks.OwnsCart do
  @moduledoc """
  Policy check for cart item create actions. Verifies that the actor owns the
  cart referenced by `cart_id` in the changeset, either via user ownership or
  matching session_id.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor owns the cart"

  @impl true
  def match?(nil, _context, _opts), do: false

  @impl true
  def match?(actor, context, _opts) do
    cart_id = Ash.Changeset.get_attribute(context.subject, :cart_id)

    if is_nil(cart_id) do
      false
    else
      require Ash.Query

      SupervisedSlices.Cart.Cart
      |> Ash.Query.filter(id == ^cart_id)
      |> Ash.read_one(authorize?: false, tenant: context.subject.tenant)
      |> case do
        {:ok, %SupervisedSlices.Cart.Cart{} = cart} ->
          dbg(cart.session_id == actor.id)
          cart.session_id == actor.id

        _ ->
          false
      end
    end
  end
end
