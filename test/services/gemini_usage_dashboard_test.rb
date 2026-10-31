require "test_helper"

class GeminiUsageDashboardTest < ActiveSupport::TestCase
  setup do
    AiApiRequest.delete_all
    @setting = AiSetting.current
    @model = "gemini-3.6-flash"
    @setting.update!(model_limits: { @model => { "rpm" => 5, "tpm" => 1000, "rpd" => 100 } })
  end

  test "combines all features and counts every accepted provider call under the actual model" do
    now = Time.zone.parse("2026-10-15 12:00:00")
    record(at: now - 10.seconds, feature: "assistant")
    record(at: now - 20.seconds, feature: "variable_chat")
    record(at: now - 2.minutes, feature: "meeting")
    record(at: now - 5.seconds, status: 429)
    record(at: now - 2.seconds, model: "gemini-3.1-flash-lite")
    record(at: now - 1.second, fingerprint: "other-key")
    card = GeminiUsageDashboard.new(@setting, now: now).cards.find { |entry| entry[:model] == @model }
    assert_equal [2, 200, 3], card[:metrics].map { |m| m[:used] }
    assert_kind_of Integer, card[:daily][:input_tokens]
    assert_equal [3, 800, 97], card[:metrics].map { |m| m[:remaining] }
    assert_equal 4, card[:daily][:attempts]
    assert_equal 1, card[:daily][:rate_limited]
    assert_equal [1, 0, 1, 1, 0, 0], card[:features].values
    assert_equal 0, card[:features]["Resumo do dia"]
    assert_equal 429, card[:latest].http_status
  end

  test "daily quotas reset at Pacific midnight even during the daylight saving change" do
    now = Time.utc(2026, 11, 1, 20)
    dashboard = GeminiUsageDashboard.new(@setting, now: now)
    assert_equal Time.utc(2026, 11, 1, 7), dashboard.day_start
    assert_equal 25.hours, dashboard.day_end - dashboard.day_start
    record(at: dashboard.day_start - 1.second)
    record(at: dashboard.day_start)
    record(at: now + 1.second)
    card = dashboard.cards.find { |entry| entry[:model] == @model }
    assert_equal 1, card[:daily][:accepted]
    assert_equal 99, card[:metrics].last[:remaining]
  end

  test "unknown tokens do not produce a false remaining balance and exhausted limits never go negative" do
    now = Time.current
    record(at: now - 1.second, input_tokens: nil)
    @setting.update!(model_limits: { @model => { "rpm" => 0, "tpm" => 1000 } })
    card = GeminiUsageDashboard.new(@setting, now: now).cards.first
    assert_equal 0, card[:metrics].first[:remaining]
    assert_nil card[:metrics][1][:used]
    assert_nil card[:metrics][1][:remaining]
    assert_nil card[:metrics][2][:remaining]
    assert_nil card[:metrics][2][:limit]
  end

  private

  def record(at:, model: @model, feature: "assistant", status: 200, fingerprint: AiApiRequest.current_credential_fingerprint, input_tokens: 100)
    AiApiRequest.create!(model: model, feature: feature, requested_at: at, http_status: status,
      credential_fingerprint: fingerprint, duration_ms: 20, input_tokens: status == 200 ? input_tokens : nil,
      output_tokens: status == 200 ? 20 : nil)
  end
end
