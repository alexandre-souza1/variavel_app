require "test_helper"
require Rails.root.join("db/migrate/20261008120000_make_inbox_personal")

class MakeInboxPersonalTest < ActiveSupport::TestCase
  def after_teardown
    super
    ActiveRecord::Base.connection_pool.connections.each(&:clear_cache!)
    Bucket.reset_column_information
  end

  test "consolidates legacy tasks by creator while preserving task details and label history" do
    prepare_legacy_schema
    first = legacy_inbox(action_plans(:one))
    second = legacy_inbox(action_plans(:two))
    tasks(:one).update_columns(bucket_id: first.id)
    tasks(:two).update_columns(bucket_id: first.id)
    third = MakeInboxPersonal::LegacyTask.create!(title: "Outra ideia do mesmo criador", creator_id: users(:one).id,
      bucket_id: second.id, start_at: Time.current)
    checklist_id = tasks(:one).tasklist.id
    comment_ids = tasks(:one).comments.pluck(:id)
    label_names = tasks(:one).labels.pluck(:name)
    assignments = tasks(:one).user_ids

    migrate_inboxes

    owner_inbox = users(:one).personal_inbox!
    assert_equal owner_inbox.id, tasks(:one).reload.bucket_id
    assert_equal owner_inbox.id, third.reload.bucket_id
    assert_equal users(:two).personal_inbox!.id, tasks(:two).reload.bucket_id
    assert_nil owner_inbox.action_plan_id
    assert_equal 2, Bucket.where(inbox: true).count
    assert_not Bucket.exists?(first.id)
    assert_not Bucket.exists?(second.id)
    assert_equal checklist_id, tasks(:one).tasklist.id
    assert_equal comment_ids, tasks(:one).comments.pluck(:id)
    assert_equal assignments, tasks(:one).user_ids
    assert_empty tasks(:one).labels
    assert_equal label_names, tasks(:one).task_activities.last.metadata.fetch("previous_labels").map { |label| label.fetch("name") }
  end

  test "legacy inboxes with gerot indicators remain plan buckets with their links and tasks" do
    prepare_legacy_schema
    plan = action_plans(:one)
    inbox = legacy_inbox(plan)
    # The old model included the plan's Entrada among its GEROT categories.
    template = Routines::PlanTemplateBuilder.call(action_plan: plan, attributes: { name: "Modelo legado" })
    category = template.routine_categories.find_by!(bucket_id: inbox.id)
    indicator = category.routine_indicators.create!(name: "Indicador legado", position: 0,
      calculation_type: :ranged, value_type: :decimal)
    mapping_id = category.routine_category_buckets.first.id
    tasks(:one).update_columns(bucket_id: inbox.id)

    migrate_inboxes

    preserved = Bucket.find(inbox.id)
    assert_not preserved.inbox?
    assert_equal plan, preserved.action_plan
    assert_equal preserved.id, tasks(:one).reload.bucket_id
    assert_equal preserved.id, category.reload.bucket_id
    assert_equal category.id, indicator.reload.routine_category_id
    assert RoutineCategoryBucket.exists?(mapping_id)
  end

  private

  def prepare_legacy_schema
    connection = ActiveRecord::Base.connection
    connection.remove_check_constraint :buckets, name: "buckets_owner_matches_inbox"
    connection.remove_index :buckets, name: "index_buckets_on_personal_inbox_owner"
    connection.remove_reference :buckets, :user, foreign_key: true
    connection.change_column_null :buckets, :action_plan_id, false
    connection.clear_cache!
    MakeInboxPersonal::LegacyBucket.reset_column_information
  end

  def legacy_inbox(plan)
    MakeInboxPersonal::LegacyBucket.create!(name: "Entrada", position: -1, inbox: true, action_plan_id: plan.id)
  end

  def migrate_inboxes
    migration = MakeInboxPersonal.new
    migration.suppress_messages { migration.up }
    Bucket.reset_column_information
    ActiveRecord::Base.connection_pool.connections.each(&:clear_cache!)
  end
end
