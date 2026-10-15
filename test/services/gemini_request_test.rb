require "test_helper"
require "minitest/mock"

class GeminiRequestTest < ActiveSupport::TestCase
  test "records reported usage and status without retaining prompts answers or the key" do
    response = Faraday::Response.new(status: 200, body: {
      usage: { total_input_tokens: 150, total_output_tokens: 70, total_tokens: 250 },
      outputs: [{ text: "Resposta privada" }]
    }.to_json)
    result = GeminiRequest.track(model: "gemini-3.6-flash", feature: "assistant", api_key: "private-key", user: users(:two)) { response }
    assert_same response, result
    record = AiApiRequest.last
    assert_equal [150, 70, 250], [record.input_tokens, record.output_tokens, record.total_tokens]
    assert_equal 200, record.http_status
    assert_equal "assistant", record.feature
    assert_equal users(:two).id, record.user_id
    refute_includes record.attributes.values, "private-key"
    refute_includes record.attributes.values, "Resposta privada"
    assert record.duration_ms >= 0
  end

  test "missing usage stays unknown and invalid provider responses still get recorded" do
    ["not-json", { outputs: [{ text: "Resposta" }] }.to_json, { usage: "invalid" }.to_json].each do |body|
      assert_difference "AiApiRequest.count" do
        GeminiRequest.track(model: "gemini-3.6-flash", feature: "meeting", api_key: "key") { Faraday::Response.new(status: 200, body: body) }
      end
      assert_nil AiApiRequest.last.input_tokens
    end
  end

  test "quota rejections preserve retry information and network exceptions propagate" do
    travel_to Time.zone.parse("2026-10-15 12:00:00") do
      response = Faraday::Response.new(status: 429, response_headers: { "retry-after" => "30" }, body: "{}")
      GeminiRequest.track(model: "gemini-3.6-flash", feature: "variable_chat", api_key: "key") { response }
      assert_equal 30.seconds.from_now, AiApiRequest.last.retry_at

      assert_raises(Faraday::TimeoutError) do
        GeminiRequest.track(model: "gemini-3.6-flash", feature: "assistant", api_key: "key") { raise Faraday::TimeoutError }
      end
      assert_nil AiApiRequest.last.http_status
      assert_nil AiApiRequest.last.input_tokens
    end
  end

  test "tracking failures cannot break a successful response or mask the provider error" do
    AiApiRequest.stub(:create!, ->(**_args) { raise ActiveRecord::StatementInvalid }) do
      response = Faraday::Response.new(status: 200, body: "not-json")
      assert_same response, GeminiRequest.track(model: "model", feature: "meeting", api_key: "key") { response }
      assert_raises(Faraday::ConnectionFailed) do
        GeminiRequest.track(model: "model", feature: "assistant", api_key: "key") { raise Faraday::ConnectionFailed }
      end
    end
  end

  test "public chat records retries and fallback calls separately" do
    with_api_key do
      responses = [provider_response(500), provider_response(429), provider_response(200)]
      service = PublicVariableChatService.new(identity: nil, history: [], question: "Teste", user: users(:two))
      service.stub(:model_candidates, %w[gemini-3.6-flash gemini-3.1-flash-lite]) do
        service.stub(:sleep, nil) do
          Faraday.stub(:post, ->(*_args, &_block) { responses.shift }) { assert_equal "Resposta", service.call }
        end
      end
      calls = AiApiRequest.where(credential_fingerprint: AiApiRequest.fingerprint("integration-key")).order(:id)
      assert_equal [500, 429, 200], calls.pluck(:http_status)
      assert_equal %w[gemini-3.6-flash gemini-3.6-flash gemini-3.1-flash-lite], calls.pluck(:model)
      assert_equal ["variable_chat"], calls.pluck(:feature).uniq
      assert_equal [users(:two).id], calls.pluck(:user_id).uniq
    end
  end

  test "meeting generation records the actual model selected after a quota rejection" do
    with_api_key do
      audio = Minitest::Mock.new
      audio.expect(:attached?, true)
      service = GeminiMeetingService.new(Struct.new(:audio).new(audio), user: users(:two))
      responses = [provider_response(429), provider_response(200, text: { summary: "Ata" }.to_json)]
      service.stub(:model_candidates, %w[gemini-3.6-flash gemini-3.1-flash-lite]) do
        Faraday.stub(:post, ->(*_args, &_block) { responses.shift }) { assert_equal({ "summary" => "Ata" }, service.call) }
      end
      calls = AiApiRequest.where(credential_fingerprint: AiApiRequest.fingerprint("integration-key")).order(:id)
      assert_equal [429, 200], calls.pluck(:http_status)
      assert_equal %w[gemini-3.6-flash gemini-3.1-flash-lite], calls.pluck(:model)
      assert_equal ["meeting"], calls.pluck(:feature).uniq
      assert_equal [users(:two).id], calls.pluck(:user_id).uniq
      audio.verify
    end
  end

  test "public chat attributes all attempts to the verified central collaborator instead of the logged in account" do
    employee = Employee.create!(nome: "Colaborador do chat", matricula: "AI-CENTRAL")
    driver = drivers(:one)
    driver.update_columns(employee_id: employee.id)
    identity = PublicVariableIdentity.new("motorista", driver)
    with_api_key do
      responses = [provider_response(500), provider_response(429), provider_response(200)]
      service = PublicVariableChatService.new(identity: identity, history: [], question: "Pergunta privada", user: users(:one))
      service.stub(:model_candidates, %w[gemini-3.6-flash gemini-3.1-flash-lite]) do
        service.stub(:sleep, nil) do
          Faraday.stub(:post, ->(*_args, &_block) { responses.shift }) { assert_equal "Resposta", service.call }
        end
      end
      calls = AiApiRequest.where(credential_fingerprint: AiApiRequest.fingerprint("integration-key")).order(:id)
      assert_equal [500, 429, 200], calls.pluck(:http_status)
      assert_equal [["Employee", employee.id]], calls.pluck(:collaborator_type, :collaborator_id).uniq
      assert_equal [nil], calls.pluck(:user_id).uniq
      calls.each do |call|
        refute_includes call.attributes.values, "Pergunta privada"
        refute_includes call.attributes.values, employee.matricula
        refute_includes call.attributes.values, employee.nome
      end
    end
  end

  private

  def provider_response(status, text: "Resposta")
    Faraday::Response.new(status: status, body: { outputs: [{ text: text }],
      usage: { total_input_tokens: 40, total_output_tokens: 10, total_tokens: 50 } }.to_json)
  end

  def with_api_key
    previous = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "integration-key"
    yield
  ensure
    ENV["GEMINI_API_KEY"] = previous
  end
end
