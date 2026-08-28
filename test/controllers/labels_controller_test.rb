require "test_helper"

class LabelsControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    post labels_url, params: { label: { name: "Nova etiqueta", color: "#000000", action_plan_id: action_plans(:one).id } }
    assert_response :success
  end
end
