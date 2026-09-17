require "test_helper"
require "minitest/mock"

class FirebasePushTest < ActiveSupport::TestCase
  setup do
    @previous_key = ENV["FIREBASE_SERVICE_ACCOUNT_JSON"]
    ENV["FIREBASE_SERVICE_ACCOUNT_JSON"] = {project_id: "workstation-test"}.to_json
    @notification = users(:one).notifications.build(id: 123, kind: "test", title: "Nova tarefa para você", body: "Revisar o relatório")
    @device = users(:one).push_devices.create!(token: "test-token", session_binding: "test", last_seen_at: Time.current)
  end

  teardown do
    ENV["FIREBASE_SERVICE_ACCOUNT_JSON"] = @previous_key
  end

  test "uses account scoped data payload with notification title and body" do
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
    assert_equal "Nova tarefa para você", payload.dig("data", "title")
    assert_equal "Revisar o relatório", payload.dig("data", "body")
  end

  test "notification preview strips markup, limits length and falls back for blank text" do
    sender = FirebasePush.new
    assert_equal "Revisar relatório", sender.send(:push_text, "<b>Revisar</b>  relatório", "Aviso", 500)
    assert_equal "Aviso", sender.send(:push_text, nil, "Aviso", 500)
    assert_equal 500, sender.send(:push_text, "á" * 600, "Aviso", 500).length
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
