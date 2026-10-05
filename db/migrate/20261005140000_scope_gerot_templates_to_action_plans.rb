class ScopeGerotTemplatesToActionPlans < ActiveRecord::Migration[7.1]
  def up
    add_reference :routine_templates, :action_plan, index: { unique: true }, foreign_key: true
    add_reference :routine_categories, :bucket, index: { unique: true }, foreign_key: true
    # Buckets may share a name; their IDs define the categories in a plan model.
    remove_index :routine_categories, name: "index_routine_categories_on_routine_template_id_and_name"
    add_index :routine_categories, %i[routine_template_id name], unique: true,
      where: "bucket_id IS NULL", name: "index_routine_categories_on_routine_template_id_and_name"
    add_reference :routine_indicators, :source_indicator,
      foreign_key: { to_table: :routine_indicators, on_delete: :nullify }
    add_index :routine_indicators, %i[routine_category_id source_indicator_id],
      unique: true, where: "source_indicator_id IS NOT NULL", name: "idx_unique_adapted_gerot_indicator"

    [RoutineTemplate, RoutineCategory, RoutineIndicator].each(&:reset_column_information)
    Routine.where.not(action_plan_id: nil).includes(:action_plan).find_each do |routine|
      categories = routine.routine_template.routine_categories
      bucket_ids = categories.to_h do |category|
        mapping = routine.action_plan.routine_category_buckets.find_by(routine_category_id: category.id)
        [category.id.to_s, mapping&.bucket_id&.to_s || "new"]
      end
      Routines::PlanLinker.call(routine: routine, action_plan: routine.action_plan, bucket_ids: bucket_ids)
    end
    RoutineCategoryBucket.joins(:routine_category)
      .where(routine_categories: { bucket_id: nil }).delete_all
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Os GEROTs adaptados usam indicadores próprios do plano. Restaure o backup para desfazer a adaptação sem perder o histórico."
  end
end
