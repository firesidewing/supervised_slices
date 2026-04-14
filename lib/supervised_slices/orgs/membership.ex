defmodule SupervisedSlices.Orgs.Membership do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Orgs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "memberships"
    repo SupervisedSlices.Repo
  end

  code_interface do
    define :update_role, action: :update_role
    define :destroy, action: :destroy
    define :for_org, action: :for_org
    define :get_kitchen_membership, action: :get_kitchen_membership, args: [:user_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:role, :organization_id, :user_id]
    end

    update :update_role do
      accept [:role]
    end

    read :for_org do
      prepare build(load: [:user])
    end

    read :get_kitchen_membership do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id) and role in [:admin, :staff])
      prepare build(load: [:organization], sort: [inserted_at: :desc])
    end

    create :invite do
      description "Invite a user by email to this organisation. Finds an existing user by email or creates a new one, then creates the membership. Newly created users receive a password-set link."

      accept [:organization_id]
      argument :email, :ci_string, allow_nil?: false
      argument :role, :atom, allow_nil?: false, constraints: [one_of: [:admin, :staff]]

      change set_attribute(:role, arg(:role))

      change fn changeset, _context ->
        email = Ash.Changeset.get_argument(changeset, :email)

        {user, freshly_created} =
          case SupervisedSlices.Accounts.User
               |> Ash.Query.for_read(:get_by_email, %{email: email})
               |> Ash.read_one(authorize?: false) do
            {:ok, %SupervisedSlices.Accounts.User{} = existing} ->
              {existing, false}

            _ ->
              created =
                SupervisedSlices.Accounts.User
                |> Ash.Changeset.for_create(:create_invited, %{email: email})
                |> Ash.create!(authorize?: false)

              {created, true}
          end

        changeset
        |> Ash.Changeset.force_change_attribute(:user_id, user.id)
        |> Ash.Changeset.put_context(:invited_user, user)
        |> Ash.Changeset.put_context(:freshly_created, freshly_created)
      end

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn changeset, membership ->
          if Ash.Changeset.get_context(changeset, :freshly_created) do
            user = Ash.Changeset.get_context(changeset, :invited_user)

            SupervisedSlices.Accounts.User
            |> Ash.ActionInput.for_action(:request_password_reset_token, %{email: user.email})
            |> Ash.run_action(authorize?: false)
          end

          {:ok, membership}
        end)
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)

      authorize_if expr(
                     exists(
                       organization.memberships,
                       user_id == ^actor(:id) and role == :admin
                     )
                   )
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:superadmin, true)

      authorize_if expr(
                     exists(
                       organization.memberships,
                       user_id == ^actor(:id) and role == :admin
                     )
                   )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      constraints one_of: [:admin, :staff, :customer]
      default :customer
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, SupervisedSlices.Orgs.Organization do
      allow_nil? false
      public? true
    end

    belongs_to :user, SupervisedSlices.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_user_org, [:user_id, :organization_id]
  end
end
