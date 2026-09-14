require "test_helper"

class MeetingMinutesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:one) }

  test "lista as atas do action plan" do
    get action_plan_meeting_minutes_url(action_plans(:one))

    assert_response :success
    assert_select "h1", /Atas de reunião/
    assert_select ".meeting-minute-index-empty"
  end
end
