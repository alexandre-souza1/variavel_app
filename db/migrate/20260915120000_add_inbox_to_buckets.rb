class AddInboxToBuckets < ActiveRecord::Migration[7.1]
  def up
    add_column :buckets, :inbox, :boolean, null: false, default: false

    Bucket.reset_column_information
    ActionPlan.find_each do |action_plan|
      next if action_plan.buckets.unscoped.exists?(inbox: true)

      action_plan.buckets.create!(name: "Entrada", position: -1, inbox: true)
    end
  end

  def down
    Bucket.where(inbox: true).delete_all
    remove_column :buckets, :inbox
  end
end
