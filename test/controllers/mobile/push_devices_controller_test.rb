require "test_helper"

class Mobile::PushDevicesControllerTest < ActionDispatch::IntegrationTest
  test "registration requires authentication" do
    sign_out users(:one)
    assert_no_difference "PushDevice.count" do
      post mobile_push_device_path, params: { token: "test-device" }, as: :json
    end
    assert_response :unauthorized
  end

  test "registers device to authenticated user not supplied user" do
    post mobile_push_device_path, params: { token: "test-device", user_id: users(:two).id }, as: :json
    assert_response :success
    device = PushDevice.find_by!(token: "test-device")
    assert_equal users(:one), device.user
    assert device.session_binding.present?
    post mobile_push_device_path, params: { token: "test-device" }, as: :json
    assert_equal 1, PushDevice.where(token: "test-device").count
  end

  test "revoking one session preserves other devices" do
    other = users(:one).push_devices.create!(token: "other-device", session_binding: "other", last_seen_at: Time.current)
    post mobile_push_device_path, params: { token: "test-device" }, as: :json
    delete mobile_push_device_path, as: :json
    assert_response :no_content
    assert_not PushDevice.exists?(token: "test-device")
    assert PushDevice.exists?(other.id)
  end

  test "logout revokes devices for this session" do
    post mobile_push_device_path, params: { token: "test-device" }, as: :json
    delete destroy_user_session_path
    assert_not PushDevice.exists?(token: "test-device")
  end

  test "invalid token is rejected" do
    post mobile_push_device_path, params: { token: "x" * 2049 }, as: :json
    assert_response :unprocessable_entity
  end

  test "notification tap marks own notification and follows its local destination" do
    notification = users(:one).notifications.create!(kind: "test", title: "Test", action_url: "/dashboard")
    get mobile_notification_path(notification)
    assert_redirected_to "/dashboard"
    assert notification.reload.read?
  end

  test "notification tap cannot open another users notification" do
    notification = users(:two).notifications.create!(kind: "test", title: "Private", action_url: "/dashboard")
    get mobile_notification_path(notification)
    assert_response :not_found
    assert_not notification.reload.read?
  end

  test "notification tap rejects external destinations" do
    notification = users(:one).notifications.create!(kind: "test", title: "Test", action_url: "//attacker.example/path")
    get mobile_notification_path(notification)
    assert_redirected_to root_path
  end
end
