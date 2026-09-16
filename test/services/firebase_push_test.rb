require "test_helper"
require "minitest/mock"

class FirebasePushTest < ActiveSupport::TestCase
  setup do
    @previous_key = ENV["FIREBASE_SERVICE_ACCOUNT_JSON"]
    ENV["FIREBASE_SERVICE_ACCOUNT_JSON"] = {project_id: "workstation-test"}.to_json
    @notification = users(:one).notifications.build(id: 123, kind: "test", title: "Private title")
    @device = users(:one).push_devices.create!(token: "test-token", session_binding: "test", last_seen_at: Time.current)
  end

  teardown do
    ENV["FIREBASE_SERVICE_ACCOUNT_JSON"] = @previous_key
  end

  test "uses account scoped data payload without private notification contents" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    sent = nil
    http = Object.new
    http.define_singleton_method(:request) { |request| sent = request; response }
    Net::HTTP.stub(:start, ->(*_args, **_options, &block) { block.call(http) }) do
      FirebasePush.new.stub(:access_token, "test-bearer") do |sender|
        assert sender.deliver(notification: @notification, device: @device)
      end
    end
    payload = JSON.parse(sent.body).fetch("message")
    assert_equal "test-token", payload["token"]
    assert_equal users(:one).id.to_s, payload.dig("data", "user_id")
    assert_equal "123", payload.dig("data", "notification_id")
    assert_nil payload["notification"]
    assert_not_includes sent.body, "Private title"
  end

  test "removes unregistered devices" do
    response = Net::HTTPNotFound.new("1.1", "404", "Not found")
    response.define_singleton_method(:body) { {error: {details: [{errorCode: "UNREGISTERED"}]}}.to_json }
    http = Object.new
    http.define_singleton_method(:request) { |_request| response }
    Net::HTTP.stub(:start, ->(*_args, **_options, &block) { block.call(http) }) do
      FirebasePush.new.stub(:access_token, "test-bearer") do |sender|
        assert_equal false, sender.deliver(notification: @notification, device: @device)
      end
    end
    assert_not PushDevice.exists?(@device.id)
  end

  test "temporary failure raises a retryable error without including token or response" do
    response = Net::HTTPTooManyRequests.new("1.1", "429", "Too many requests")
    response.define_singleton_method(:body) { "sensitive-response" }
    http = Object.new
    http.define_singleton_method(:request) { |_request| response }
    Net::HTTP.stub(:start, ->(*_args, **_options, &block) { block.call(http) }) do
      FirebasePush.new.stub(:access_token, "test-bearer") do |sender|
        error = assert_raises(FirebasePush::DeliveryError) { sender.deliver(notification: @notification, device: @device) }
        assert_equal "FCM HTTP 429", error.message
      end
    end
    assert PushDevice.exists?(@device.id)
  end
end
