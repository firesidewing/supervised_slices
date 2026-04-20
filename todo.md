- [x] async assings for admin page
- [x] loading states on all button interactions (disable, spinner, etc.)
- [x] show/hide modifier groups, hide by default to enable a wider menu editor.
- [x] have the menu respect the sort order, both in the admin and the menu (maybe allow drag drop for menu editing)
- [x] set up menu uploader using the service
- [x] adjust wording (Atelier)
- [x] scope analytics to open periods
- [ ] group editing is expanding out of container
- [ ] no url for images
- [ ] can't delete menu item ( 00:00:09   > Error returned from: SupervisedSlices.Menu.MenuItem.destroy
00:00:09 Unknown Error
00:00:09 * ** (Ecto.ConstraintError) constraint error when attempting to insert struct:
00:00:09     * "order_items_menu_item_id_fkey" (foreign_key_constraint)
00:00:09 If you would like to stop this constraint violation from raising an
00:00:09 exception and instead add it as an error to your changeset, please
00:00:09 call `foreign_key_constraint/3` on your changeset with the constraint
00:00:09 `:name` as an option.
00:00:09 The changeset defined the following constraints:
00:00:09     * "menu_item_images_menu_item_id_fkey" (foreign_key_constraint)
00:00:09     * "menu_item_sizes_menu_item_id_fkey" (foreign_key_constraint)
00:00:09     * "menu_categories_id_fkey" (foreign_key_constraint)
00:00:09     * "menu_items_modifier_groups_menu_item_id_fkey" (foreign_key_constraint)
00:00:09     * "menu_items_pkey" (unique_constraint)
00:00:09     * "menu_items_available_index" (unique_constraint)
00:00:09   (ash 3.22.1) /app/deps/splode/lib/splode.ex:434: Ash.Error.to_error/2
00:00:09   (ash_postgres 2.8.0) lib/data_layer.ex:2723: AshPostgres.DataLayer.handle_raised_error/4
00:00:09   (ash 3.22.1) lib/ash/changeset/changeset.ex:5116: Ash.Changeset.run_around_actions/2
00:00:09     (ash 3.22.1) lib/ash/actions/destroy/destroy.ex:82: Ash.Actions.Destroy.run/4
00:00:09     (ash 3.22.1) lib/ash.ex:3827: Ash.destroy/2
)
- [ ] better editor for modifier groups, maybe their own section?
- [ ] hide non live items from menu
- [ ] Actual radio control type for exclusive options.
