require "test_helper"

class RoutineTemplatesControllerTest < ActionDispatch::IntegrationTest
  test "shows only templates from the current user sector" do
    user = User.create!(email: "fleet_user_#{SecureRandom.hex(4)}@example.com", password: "password123", role: :user, sector: :fleet)
    sign_in user

    fleet_template = RoutineTemplate.create!(name: "Fleet template #{SecureRandom.hex(4)}", sector: :fleet)
    du_template = RoutineTemplate.create!(name: "DU template #{SecureRandom.hex(4)}", sector: :du)

    visible_ids = RoutineTemplate.visible_to(user).where(id: [fleet_template.id, du_template.id]).pluck(:id)
    assert_equal [fleet_template.id], visible_ids
  end

  test "admin sees all templates" do
    user = User.create!(email: "admin_user_#{SecureRandom.hex(4)}@example.com", password: "password123", role: :admin, sector: :fleet)
    sign_in user

    fleet_template = RoutineTemplate.create!(name: "Fleet admin #{SecureRandom.hex(4)}", sector: :fleet)
    du_template = RoutineTemplate.create!(name: "DU admin #{SecureRandom.hex(4)}", sector: :du)

    visible_ids = RoutineTemplate.visible_to(user).where(id: [fleet_template.id, du_template.id]).pluck(:id)
    assert_equal [fleet_template.id, du_template.id].sort, visible_ids.sort
  end
end
