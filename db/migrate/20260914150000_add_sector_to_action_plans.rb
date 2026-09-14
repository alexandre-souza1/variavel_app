class AddSectorToActionPlans < ActiveRecord::Migration[7.1]
  def up
    add_column :action_plans, :sector, :integer

    execute <<~SQL
      UPDATE action_plans
      SET sector = users.sector
      FROM users
      WHERE users.id = action_plans.user_id
    SQL
  end

  def down
    remove_column :action_plans, :sector
  end
end
