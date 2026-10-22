require 'test_helper'
require 'minitest/mock'

class AiAssistantFailuresJobTest < ActiveJob::TestCase
  setup do
    @conversation = AiConversation.create!(user: users(:one), request_token: 'fail-1', requested_at: Time.current)
    @message = @conversation.ai_messages.create!(role: 'user', content: 'Pergunta privada de teste')
    @previous_key = ENV['GEMINI_API_KEY']
    ENV['GEMINI_API_KEY'] = 'private-test-key'
  end

  teardown { ENV['GEMINI_API_KEY'] = @previous_key }

  test 'a timeout tries an alternative model and preserves request tracking' do
    requests = run_provider do |request, index|
      raise Faraday::TimeoutError, 'sensitive-provider-body' if index == 1
      Faraday::Response.new(status: 200, body: { outputs: [{ text: 'Resposta recuperada.' }] }.to_json)
    end
    assert_equal 2, requests.size
    refute_equal requests.first[:body]['model'], requests.last[:body]['model']
    assert requests.all? { |request| request[:timeout] <= 45 && request[:timeout] > 25 }
    assert_nil @conversation.reload.error_message
    assert_equal 'Resposta recuperada.', @conversation.ai_messages.last.content
    assert_equal [nil, 200], AiApiRequest.order(:id).last(2).pluck(:http_status)
  end

  test 'timeouts exhausted produce a useful message and correlated safe diagnostic logs' do
    output = StringIO.new
    requests = nil
    Rails.stub(:logger, ActiveSupport::Logger.new(output)) do
      requests = run_provider { raise Faraday::TimeoutError, 'private-test-key sensitive-provider-body' }
    end
    assert_equal 3, requests.size
    refute @conversation.reload.processing?
    assert_includes @conversation.error_message, 'Gemini demorou além do limite'
    reference = @conversation.error_message[/IA-[A-F0-9]{12}/]
    assert reference
    assert_includes output.string, reference
    assert_includes output.string, 'ai_assistant_failure'
    assert_includes output.string, 'timeout'
    refute_includes output.string, 'private-test-key'
    refute_includes output.string, 'sensitive-provider-body'
    refute_includes output.string, @message.content
  end

  test 'HTTP refusals expose the reason without exposing the provider body' do
    { 400 => 'formato da consulta', 401 => 'chave ou a permissão', 403 => 'chave ou a permissão',
      404 => 'modelo de IA configurado', 429 => 'limite de uso', 503 => 'indisponível' }.each do |status, expected|
      @conversation.update!(request_token: 'fail-1')
      requests = run_provider { Faraday::Response.new(status: status, body: 'sensitive-provider-body') }
      assert_equal [400, 401, 403].include?(status) ? 1 : 3, requests.size
      assert_includes @conversation.reload.error_message, expected
      assert_match(/IA-[A-F0-9]{12}/, @conversation.error_message)
      refute_includes @conversation.error_message, 'sensitive-provider-body'
    end
  end

  test 'connection errors and malformed responses are distinct from an internal error' do
    run_provider { raise Faraday::ConnectionFailed }
    assert_includes @conversation.reload.error_message, 'conectar ao Gemini'
    @conversation.update!(request_token: 'fail-1')
    run_provider { Faraday::Response.new(status: 200, body: '<invalid-json>') }
    assert_includes @conversation.reload.error_message, 'resposta inválida'
  end

  test 'the total deadline prevents another provider attempt' do
    responder = AiAssistant::Responder.new(user: @conversation.user, conversation: @conversation, message: @message)
    responder.instance_variable_set(:@deadline, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
    error = Faraday.stub(:post, ->(*) { flunk 'An expired deadline must not start a request' }) do
      assert_raises(AiAssistant::Responder::Unavailable) { responder.send(:request, [], final: false) }
    end
    assert_equal :timeout, error.reason
  end

  private

  def run_provider(&response)
    requests = []
    post = lambda do |_url, &block|
      request = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new)
      block.call(request)
      requests << { body: JSON.parse(request.body), timeout: request.options.timeout }
      response.call(request, requests.size)
    end
    Faraday.stub(:post, post) { AiAssistantJob.perform_now(@conversation.id, 'fail-1', @message.id) }
    requests
  end
end
