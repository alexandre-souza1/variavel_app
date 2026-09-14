require "test_helper"

class LabelsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
  end

  test "should get create" do
    post labels_url, params: { label: { name: "Nova etiqueta", color: "#000000", action_plan_id: action_plans(:one).id } }
    assert_response :success
  end

  test "destroy removes a label from its tasks before deleting it" do
    label = labels(:one)
    task = tasks(:one)

    assert_equal 1, task.task_labels.where(label: label).count

    assert_difference -> { Label.count }, -1 do
      delete action_plan_label_url(label.action_plan, label)
    end

    assert_response :redirect
    assert_not Label.exists?(label.id)
    assert_empty task.reload.task_labels.where(label_id: label.id)
  end
end
