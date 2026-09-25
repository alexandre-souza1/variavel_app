require "test_helper"

class ActionPlansControllerTest < ActionDispatch::IntegrationTest
  test "new renders the plan form without the meeting recorder" do
    get new_action_plan_url

    assert_response :success
    assert_select 'form[action=?]', action_plans_path
    assert_select "#meeting-recorder-widget", count: 0
  end

  test "invalid creation renders the form without the meeting recorder" do
    assert_no_difference("ActionPlan.count") do
      post action_plans_url, params: { action_plan: { name: "" } }
    end

    assert_response :success
    assert_select 'form[action=?]', action_plans_path
    assert_select "#meeting-recorder-widget", count: 0
  end

  test "saved plans still display the meeting recorder" do
    action_plan = users(:one).action_plans.create!(name: "Plano de melhoria")

    get action_plan_url(action_plan)

    assert_response :success
    assert_select "#meeting-recorder-widget" do
      assert_select 'form[action=?]', action_plan_meeting_minutes_path(action_plan)
    end
  end
end
