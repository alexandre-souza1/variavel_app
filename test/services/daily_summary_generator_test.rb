require "test_helper"
require "minitest/mock"

class DailySummaryGeneratorTest < ActiveSupport::TestCase
  setup do
    @previous_key = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "daily-summary-test-key"
    @user = users(:two)
    @user.update!(role: :mechanical, sector: :fleet)
    AiSetting.current.update!(primary_model: "gemini-3.6-flash")
  end

  teardown { ENV["GEMINI_API_KEY"] = @previous_key }

  test "sends the existing permission-scoped briefing to Gemini without changing the personal conversation" do
    Task.create!(title: "Minha tarefa de hoje", bucket: @user.personal_inbox!, creator: @user,
      due_at: Time.current.end_of_day)
    other = users(:one)
    Task.create!(title: "Tarefa privada de outra conta", bucket: other.personal_inbox!, creator: other,
      due_at: Time.current.end_of_day)
    payload = nil
    transport = lambda do |url, &block|
      request = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new, nil)
      block.call(request)
      assert_equal GeminiMeetingService::ENDPOINT, url
      payload = JSON.parse(request.body)
      response
    end

    result = nil
    assert_no_difference ["AiConversation.count", "AiMessage.count", "Notification.count"] do
      Faraday.stub(:post, transport) { result = generator.call }
    end

    brief = JSON.parse(payload.fetch("input").first.fetch("text")).fetch("briefing")
    assert_includes brief.fetch("personal_tasks").fetch("records").pluck("title"), "Minha tarefa de hoje"
    assert_empty brief.fetch("sections")
    refute_includes payload.to_json, "Tarefa privada de outra conta"
    assert_equal false, payload["store"]
    assert_nil payload["tools"]
    assert_equal "**Agenda**\n- Minha tarefa de hoje", result[:content]
    assert_equal "daily_summary", AiApiRequest.last.feature
    assert_equal @user.id, AiApiRequest.last.user_id
    assert_equal 150, AiApiRequest.last.total_tokens
    assert result[:sources].any? { |source| source[:path] == Rails.application.routes.url_helpers.inbox_path }
  end

  test "supports the interactions steps response" do
    body = { status: "completed", steps: [{ type: "model_output", content: [{ type: "text", text: "Agenda do dia" }] }] }.to_json
    Faraday.stub(:post, ->(*) { Faraday::Response.new(status: 200, body: body) }) do
      assert_equal "Agenda do dia", generator.call[:content]
    end
  end

  test "quota and network failures fall back to another configured model" do
    attempts = 0
    transport = ->(*) do
      attempts += 1
      case attempts
      when 1 then Faraday::Response.new(status: 429, body: "{}")
      when 2 then raise Faraday::ConnectionFailed
      else response
      end
    end

    Faraday.stub(:post, transport) { assert_equal "**Agenda**\n- Minha tarefa de hoje", generator.call[:content] }
    assert_equal 3, attempts
    assert_equal [429, nil, 200], AiApiRequest.order(:id).last(3).map(&:http_status)
  end

  test "invalid provider output is never treated as a delivered summary" do
    ["invalid-json", "{}", '{"outputs":[{"text":""}]}', '{"status":"failed","outputs":[{"text":"No"}]}'].each do |body|
      Faraday.stub(:post, ->(*) { Faraday::Response.new(status: 200, body: body) }) do
        error = assert_raises(AiAssistant::Responder::Unavailable) { generator.call }
        assert_equal :invalid_response, error.reason
      end
    end
  end

  test "authentication failures do not try another model" do
    attempts = 0
    Faraday.stub(:post, ->(*) { attempts += 1; Faraday::Response.new(status: 403, body: "{}") }) do
      error = assert_raises(AiAssistant::Responder::Unavailable) { generator.call }
      assert_equal :authentication, error.reason
    end
    assert_equal 1, attempts
  end

  test "missing configuration or an inactive account never calls Gemini" do
    Faraday.stub(:post, ->(*) { flunk "No request should be sent" }) do
      ENV.delete("GEMINI_API_KEY")
      error = assert_raises(AiAssistant::Responder::Unavailable) { generator.call }
      assert_equal :not_configured, error.reason

      ENV["GEMINI_API_KEY"] = "daily-summary-test-key"
      @user.update!(active: false)
      error = assert_raises(AiAssistant::Responder::Unavailable) { generator.call }
      assert_equal :invalid_request, error.reason
    end
  end

  private

  def generator
    AiAssistant::DailySummaryGenerator.new(user: @user)
  end

  def response
    Faraday::Response.new(status: 200, body: {
      outputs: [{ type: "text", text: "**Agenda**\n- Minha tarefa de hoje" }],
      usage: { total_input_tokens: 100, total_output_tokens: 50, total_tokens: 150 }
    }.to_json)
  end
end
