require "test_helper"

class RoutinesControllerTest < ActionDispatch::IntegrationTest
  test "shows only routines from the current user sector" do
    user = User.create!(email: "fleet_routine_user_#{SecureRandom.hex(4)}@example.com", password: "password123", role: :user, sector: :fleet)
    sign_in user

    fleet_template = RoutineTemplate.create!(name: "Fleet routine template #{SecureRandom.hex(4)}", sector: :fleet)
    du_template = RoutineTemplate.create!(name: "DU routine template #{SecureRandom.hex(4)}", sector: :du)

    fleet_routine = Routine.create!(
      routine_template: fleet_template,
      created_by: user,
      title: "Fleet routine",
      period_start: Date.new(2026, 7, 1),
      period_end: Date.new(2026, 7, 31),
      status: :draft
    )

    du_routine = Routine.create!(
      routine_template: du_template,
      created_by: user,
      title: "DU routine",
      period_start: Date.new(2026, 8, 1),
      period_end: Date.new(2026, 8, 31),
      status: :draft
    )

    visible_ids = Routine.visible_to(user).where(id: [fleet_routine.id, du_routine.id]).pluck(:id)
    assert_equal [fleet_routine.id], visible_ids
  end
end
