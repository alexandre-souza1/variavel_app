class AllowBucketCategoryNamesInPlanModels < ActiveRecord::Migration[7.1]
  def up
    name = "index_routine_categories_on_routine_template_id_and_name"
    index = connection.indexes(:routine_categories).find { |definition| definition.name == name }
    return if index&.where.present?

    # Upgrade databases that ran the first version of the plan-model migration.
    remove_index :routine_categories, name: name
    add_index :routine_categories, %i[routine_template_id name], unique: true,
      where: "bucket_id IS NULL", name: name
  end

  def down
    # The constraint belongs to ScopeGerotTemplatesToActionPlans as well.
  end
end
