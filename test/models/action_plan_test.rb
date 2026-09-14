require "test_helper"

class ActionPlanTest < ActiveSupport::TestCase
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
