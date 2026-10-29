require "test_helper"

class ActionPlanTest < ActiveSupport::TestCase
  test "archives and restores a plan while preserving its tasks and gerots" do
    plan = users(:one).action_plans.create!(name: "Plano anual")
    task = plan.buckets.first.tasks.create!(title: "Ação pendente", creator: users(:one))
    template = Routines::PlanTemplateBuilder.call(action_plan: plan, attributes: { name: "Modelo anual" })
    gerot = plan.routines.create!(routine_template: template, created_by: users(:one),
      title: "Outubro", period_start: Date.new(2026, 10, 1), period_end: Date.new(2026, 10, 31))
    bucket_ids = plan.buckets.ids

    freeze_time do
      plan.archive!
      assert_equal Time.current, plan.reload.archived_at
    end
    assert plan.archived?
    assert_includes ActionPlan.archived, plan
    assert_not_includes ActionPlan.active, plan
    assert_equal bucket_ids.sort, plan.buckets.ids.sort
    assert_equal plan.buckets.first.id, task.reload.bucket_id
    assert_not task.completed?
    assert_equal plan.id, gerot.reload.action_plan_id

    original_archived_at = plan.archived_at
    travel 1.day do
      plan.archive!
      assert_equal original_archived_at, plan.reload.archived_at
    end

    plan.unarchive!
    assert_nil plan.reload.archived_at
    assert_not plan.archived?
    assert_includes ActionPlan.active, plan
    assert_not_includes ActionPlan.archived, plan
    assert_equal plan.id, gerot.reload.action_plan_id
    assert Task.exists?(task.id)
  end

  test "inherits the sector from its owner" do
    user = users(:one)
    user.update!(sector: :du)

    plan = ActionPlan.new(name: "Plano", user: user)

    assert plan.valid?
    assert_equal "du", plan.sector
  end

  test "keeps an explicitly selected sector" do
    user = users(:one)
    user.update!(sector: :fleet)

    plan = ActionPlan.new(name: "Plano", user: user, sector: :du)

    assert plan.valid?
    assert_equal "du", plan.sector
  end

  test "allows a missing sector when the owner has no sector" do
    user = users(:one)
    user.update!(sector: nil)

    plan = ActionPlan.new(name: "Plano", user: user)

    assert plan.valid?
    assert_nil plan.sector
  end

  test "shows private plans to users from its sector and assigned users" do
    owner = users(:one)
    owner.update!(sector: :fleet)
    other_user = users(:two)
    other_user.update!(sector: :du)

    private_plan = ActionPlan.create!(name: "Privado", user: owner, sector: :fleet, public: false)
    task = private_plan.buckets.first.tasks.create!(title: "Tarefa", creator: owner)
    task.users << other_user

    assert_includes ActionPlan.visible_to(owner), private_plan
    assert_includes ActionPlan.visible_to(other_user), private_plan
  end

  test "does not show a private plan to unrelated users" do
    owner = users(:one)
    owner.update!(sector: :fleet)
    unrelated_user = users(:two)
    unrelated_user.update!(sector: :du)

    private_plan = ActionPlan.create!(name: "Privado", user: owner, sector: :fleet, public: false)

    assert_not_includes ActionPlan.visible_to(unrelated_user), private_plan
  end
end
