require "test_helper"
require "minitest/mock"

class AiAssistantJobTest < ActiveJob::TestCase
  setup do
    @conversation = AiConversation.create!(user: users(:one), request_token: "request-1", requested_at: Time.current)
    @message = @conversation.ai_messages.create!(role: "user", content: "Quais são minhas tarefas?")
  end

  test "runs tool calls and persists an answer with server generated sources" do
    requests = []
    responses = [
      { "steps" => [{ "type" => "function_call", "id" => "call-1", "name" => "list_tasks", "arguments" => { "mine" => true } }] },
      { "steps" => [{ "type" => "model_output", "content" => [{ "type" => "text", "text" => "Encontrei suas tarefas." }] }] }
    ]
    fake_post = lambda do |_url, &block|
      req = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new)
      block.call(req)
      requests << JSON.parse(req.body)
      Faraday::Response.new(status: 200, body: responses.shift.to_json)
    end
    previous = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-key"
    Faraday.stub(:post, fake_post) { AiAssistantJob.perform_now(@conversation.id, "request-1", @message.id) }
    assert_equal false, @conversation.reload.processing?
    answer = @conversation.ai_messages.last
    assert_equal "assistant", answer.role
    assert_equal "Encontrei suas tarefas.", answer.content
    assert answer.sources.any?
    assert requests.all? { |request| request["store"] == false }
    assert_equal "function_result", requests.last["input"].last["type"]
    assert_equal "call-1", requests.last["input"].last["call_id"]
    calls = AiApiRequest.where(credential_fingerprint: AiApiRequest.fingerprint("test-key"))
    assert_equal [users(:one).id], calls.pluck(:user_id).uniq
  ensure
    ENV["GEMINI_API_KEY"] = previous
  end

  test "HR can prepare employee creation through provider tools without creating the employee" do
    users(:one).update!(role: :user, sector: :hr)
    @message.update!(content: "Cadastre Novo Colaborador, matrícula 001234, motorista DU, ainda em integração.")
    requests = []
    responses = [
      { "steps" => [{ "type" => "function_call", "id" => "employee-1", "name" => "prepare_employee", "arguments" => {
        "nome" => "Novo Colaborador", "matricula" => "001234", "sector" => "du", "cargo" => "motorista"
      } }] },
      { "steps" => [{ "type" => "model_output", "content" => [{ "type" => "text", "text" => "Confira os dados e clique em Confirmar cadastro." }] }] }
    ]
    fake_post = lambda do |_url, &block|
      req = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new)
      block.call(req)
      requests << JSON.parse(req.body)
      Faraday::Response.new(status: 200, body: responses.shift.to_json)
    end
    previous = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-key"
    assert_no_difference ["Employee.count", "EmployeeRole.count", "EmployeeCareerEvent.count", "Driver.count", "User.count"] do
      assert_difference "AiActionRequest.count", 1 do
        Faraday.stub(:post, fake_post) { AiAssistantJob.perform_now(@conversation.id, "request-1", @message.id) }
      end
    end
    assert_nil @conversation.reload.error_message
    action = @conversation.ai_action_requests.sole
    assert_equal "create_employee", action.kind
    assert_equal "pending", action.status
    assert_equal "001234", action.payload["matricula"]
    assert_nil action.payload["starts_on"]
    assert_includes requests.first["tools"].pluck("name"), "prepare_employee"
    refute_includes requests.to_json, action.confirmation_token
    assert requests.all? { |request| request["store"] == false }
  ensure
    ENV["GEMINI_API_KEY"] = previous
  end

  test "clearing cancels in flight replies and an old job cannot overwrite a new request" do
    @conversation.clear!
    @conversation.update!(request_token: "request-2")
    assert_no_difference "AiMessage.count" do
      @conversation.finish!("request-1", answer: { content: "Resposta antiga", sources: [] })
      AiAssistantJob.perform_now(@conversation.id, "request-1", @message.id)
    end
    assert_equal "request-2", @conversation.reload.request_token
  end

  test "provider errors release the conversation without exposing secrets" do
    AiAssistant::Responder.stub(:new, ->(**_args) { raise "sensitive-provider-body" }) do
      AiAssistantJob.perform_now(@conversation.id, "request-1", @message.id)
    end
    refute @conversation.reload.processing?
    assert_match "Não foi possível responder", @conversation.error_message
    refute_includes @conversation.error_message, "sensitive-provider-body"
  end

  test "daily briefing is available to the provider and returns only the current sector priorities" do
    users(:one).update!(role: :user, sector: :finance)
    @message.update!(content: 'O que tenho para hoje?')
    requests = []
    responses = [
      { steps: [{ type: 'function_call', id: 'daily-1', name: 'daily_briefing', arguments: {} }] },
      { steps: [{ type: 'model_output', content: [{ type: 'text', text: 'Aqui está o resumo do seu dia.' }] }] }
    ]
    post = lambda do |_url, &block|
      req = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new)
      block.call(req)
      requests << JSON.parse(req.body)
      Faraday::Response.new(status: 200, body: responses.shift.to_json)
    end
    previous = ENV['GEMINI_API_KEY']
    ENV['GEMINI_API_KEY'] = 'test-key'
    Faraday.stub(:post, post) { AiAssistantJob.perform_now(@conversation.id, 'request-1', @message.id) }
    assert_nil @conversation.reload.error_message
    names = requests.first['tools'].pluck('name')
    assert_includes names, 'daily_briefing'
    assert_includes names, 'financial_summary'
    refute_includes names, 'employee_details'
    refute_includes names, 'ai_usage'
    result = JSON.parse(requests.last['input'].last['result'].first['text'])
    assert result['sections'].key?('finance')
    refute result['sections'].key?('fleet')
    assert_match(/metas financeiras/, requests.first['system_instruction'])
    assert_equal 'Aqui está o resumo do seu dia.', @conversation.ai_messages.last.content
  ensure
    ENV['GEMINI_API_KEY'] = previous
  end

  test "an undeclared tool requested by the provider cannot bypass module permissions" do
    users(:one).update!(role: :user, sector: :warehouse)
    requests = []
    responses = [
      { steps: [{ type: 'function_call', id: 'forbidden-1', name: 'financial_summary', arguments: { sector: 'frota', user_id: users(:two).id } }] },
      { steps: [{ type: 'model_output', content: [{ type: 'text', text: 'Seu perfil não permite essa consulta.' }] }] }
    ]
    post = lambda do |_url, &block|
      req = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new)
      block.call(req)
      requests << JSON.parse(req.body)
      Faraday::Response.new(status: 200, body: responses.shift.to_json)
    end
    previous = ENV['GEMINI_API_KEY']
    ENV['GEMINI_API_KEY'] = 'test-key'
    queries = []
    ActiveSupport::Notifications.subscribed(->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }, 'sql.active_record') do
      Faraday.stub(:post, post) { AiAssistantJob.perform_now(@conversation.id, 'request-1', @message.id) }
    end
    result = JSON.parse(requests.last['input'].last['result'].first['text'])
    assert result['error']
    refute result.key?('total_amount')
    refute queries.any? { |query| query.match?(/\bFROM "invoices"\b|\bJOIN "invoices"\b/) }
    assert_nil @conversation.reload.error_message
  ensure
    ENV['GEMINI_API_KEY'] = previous
  end

  test "provider prepares a persisted private preview without executing or receiving a confirmation token" do
    requests = []
    responses = [
      { steps: [{ type: "function_call", id: "prepare-1", name: "prepare_task", arguments: {
        title: "Inspecionar pneus", due_at: "2030-10-20", checklist: ["Conferir sulcos"]
      } }] },
      { steps: [{ type: "function_call", id: "execute-1", name: "confirm_action", arguments: { approved: true } }] },
      { steps: [{ type: "model_output", content: [{ type: "text", text: "Confira a prévia e confirme pelo botão." }] }] }
    ]
    post = lambda do |_url, &block|
      req = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new)
      block.call(req)
      requests << JSON.parse(req.body)
      Faraday::Response.new(status: 200, body: responses.shift.to_json)
    end
    previous = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-key"
    assert_no_difference ["Task.count", "ActionPlan.count", "Bucket.count", "Notification.count"] do
      assert_difference "AiActionRequest.count", 1 do
        Faraday.stub(:post, post) { AiAssistantJob.perform_now(@conversation.id, "request-1", @message.id) }
      end
    end
    action = @conversation.ai_messages.last.ai_action_requests.sole
    assert_equal users(:one).id, action.user_id
    assert_equal "pending", action.status
    assert_equal "Inspecionar pneus", action.payload["title"]
    refute requests.any? { |request| request.to_json.include?(action.confirmation_token) }
    function_results = requests.last["input"].select { |step| step["type"] == "function_result" }
    assert_equal false, JSON.parse(function_results.first["result"].first["text"])["executed"]
    assert JSON.parse(function_results.last["result"].first["text"])["error"]
    assert_nil @conversation.reload.error_message
  ensure
    ENV["GEMINI_API_KEY"] = previous
  end

  test "a failed response after preparing a draft never leaves an actionable proposal" do
    calls = 0
    post = lambda do |_url, &block|
      req = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new)
      block.call(req)
      calls += 1
      if calls == 1
        Faraday::Response.new(status: 200, body: { steps: [{ type: "function_call", id: "draft-1", name: "prepare_task", arguments: { title: "Não deve ficar pendente" } }] }.to_json)
      else
        raise Faraday::TimeoutError
      end
    end
    previous = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-key"
    assert_no_difference ["AiActionRequest.count", "Task.count"] do
      Faraday.stub(:post, post) { AiAssistantJob.perform_now(@conversation.id, "request-1", @message.id) }
    end
    refute @conversation.reload.processing?
    assert @conversation.error_message.present?
  ensure
    ENV["GEMINI_API_KEY"] = previous
  end
end
