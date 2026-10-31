require "test_helper"

class NotificationPreferencesTest < ActionDispatch::IntegrationTest
  test "each authenticated user can enable and disable only their own summary" do
    sign_in users(:two)

    patch preferences_notifications_path, params: {
      user_id: users(:one).id, user: { daily_summary_enabled: "1", role: "admin", sector: "finance" }
    }, as: :json

    assert_response :success
    assert response.parsed_body["daily_summary_enabled"]
    assert users(:two).reload.daily_summary_enabled?
    assert_not users(:two).admin?
    assert_not users(:one).reload.daily_summary_enabled?

    patch preferences_notifications_path, params: { user: { daily_summary_enabled: "0" } }, as: :json
    assert_response :success
    assert_not response.parsed_body["daily_summary_enabled"]
    assert_nil users(:two).reload.daily_summary_next_run_at
  end

  test "unauthenticated visitors cannot enable delivery" do
    sign_out users(:one)
    patch preferences_notifications_path, params: { user: { daily_summary_enabled: true } }, as: :json
    assert_response :unauthorized
    assert_not users(:one).reload.daily_summary_enabled?
  end

  test "the notification bell exposes a labelled switch for every user" do
    sign_in users(:two)
    get root_path
    follow_redirect! while response.redirect?

    assert_response :success
    assert_select "#notifications-menu input[type=checkbox][role=switch][name='user[daily_summary_enabled]']"
    assert_select "#notification-daily-summary-help", text: /8h.*Brasília/
  end
end
