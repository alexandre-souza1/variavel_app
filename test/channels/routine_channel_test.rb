require "test_helper"

class RoutineChannelTest < ActionCable::Channel::TestCase
  test "uses the authenticated user rather than the requested user id" do
    user = users(:two)
    user.update!(name: "Leitor", role: :user)
    stub_connection(env: { "warden" => Struct.new(:user).new(user) })

    subscribe routine_id: routines(:one).id, user_id: users(:one).id

    assert subscription.confirmed?
    assert_equal user, subscription.instance_variable_get(:@user)
  end

  test "rejects subscriptions to gerots in inaccessible plans" do
    user = users(:two)
    user.update!(role: :user)
    plan = users(:one).action_plans.create!(name: "Plano privado", public: false, sector: :hr)
    template = Routines::PlanTemplateBuilder.call(action_plan: plan, attributes: { name: "Modelo privado" })
    routine = Routine.create!(routine_template: template, action_plan: plan, created_by: users(:one), period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 1, 31))
    stub_connection(env: { "warden" => Struct.new(:user).new(user) })

    subscribe routine_id: routine.id, user_id: users(:one).id

    assert subscription.rejected?
  end

  test "rejects unauthenticated subscriptions" do
    stub_connection(env: {})
    subscribe routine_id: routines(:one).id, user_id: users(:one).id
    assert subscription.rejected?
  end
end
