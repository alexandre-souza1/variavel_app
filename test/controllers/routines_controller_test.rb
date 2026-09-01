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
      status: :open
    )

    du_routine = Routine.create!(
      routine_template: du_template,
      created_by: user,
      title: "DU routine",
      period_start: Date.new(2026, 8, 1),
      period_end: Date.new(2026, 8, 31),
      status: :open
    )

    visible_ids = Routine.visible_to(user).where(id: [fleet_routine.id, du_routine.id]).pluck(:id)
    assert_equal [fleet_routine.id], visible_ids
  end

  test "keeps archived routines out of the main index" do
    template = RoutineTemplate.create!(
      name: "Archived index template #{SecureRandom.hex(4)}",
      sector: :fleet
    )
    archived_routine = Routine.create!(
      routine_template: template,
      created_by: users(:one),
      title: "Archived routine",
      period_start: Date.new(2026, 9, 1),
      period_end: Date.new(2026, 9, 30),
      status: :archived
    )
    open_routine = Routine.create!(
      routine_template: template,
      created_by: users(:one),
      title: "Open routine",
      period_start: Date.new(2026, 10, 1),
      period_end: Date.new(2026, 10, 31),
      status: :open
    )

    get routines_path

    assert_response :success
    assert_select "td", text: /Open routine/
    assert_select "td", text: /Archived routine/, count: 0
    assert_not_includes Routine.visible_to(users(:one))
      .where.not(status: :archived)
      .pluck(:id), archived_routine.id
    assert_includes Routine.visible_to(users(:one))
      .where(status: :archived)
      .pluck(:id), archived_routine.id
    assert_includes Routine.visible_to(users(:one))
      .where.not(status: :archived)
      .pluck(:id), open_routine.id
  end

  test "moves a routine through its lifecycle" do
    sign_in users(:one)

    template = RoutineTemplate.create!(
      name: "Lifecycle template #{SecureRandom.hex(4)}",
      sector: :fleet
    )
    routine = Routine.create!(
      routine_template: template,
      created_by: users(:one),
      title: "Lifecycle routine",
      period_start: Date.new(2026, 7, 1),
      period_end: Date.new(2026, 7, 31),
      status: :open
    )

    patch close_routine_path(routine)
    assert_redirected_to routine_path(routine)
    assert routine.reload.closed?

    patch archive_routine_path(routine)
    assert_redirected_to routine_path(routine)
    assert routine.reload.archived?

    patch reopen_routine_path(routine)
    assert_redirected_to routine_path(routine)
    assert routine.reload.open?
  end
end
