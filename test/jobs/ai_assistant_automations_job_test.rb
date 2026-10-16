require "test_helper"
require "minitest/mock"
require_relative "../support/automation_setup"

class AiAssistantAutomationsJobTest < ActiveJob::TestCase
  include AutomationSetup
  setup do
    setup_automation_data
    @conversation = AiConversation.create!(user: @owner, request_token: "step-1", requested_at: Time.current)
    @question = @conversation.ai_messages.create!(role: "user", content: "Atualize o GEROT com a soma do combustível do mês, todo dia. Me ajude a montar.")
    @requests = []
  end
  teardown { travel_back }

  test "provider guides two turns remembers choices and stages a confirmed rule without executing it" do
    responses = [
      call("automation_options", { group: "catalog" }),
      call("configure_automation", { configuration: {
        name: "Combustível automático", source_key: "invoices", operation: "sum", period: "month",
        filters: { budget_category_id: @category.id }, action_key: "update_indicator",
        action_config: { routine_template_id: @template.id, routine_indicator_id: @indicator.id }, schedule: "daily"
      } }),
      output("Em qual horário de Brasília devemos verificar?")
    ]
    without_business_writes do
      with_provider(responses) { AiAssistantJob.perform_now(@conversation.id, "step-1", @question.id) }
    end
    assert_nil @conversation.reload.error_message
    assert_empty @conversation.ai_action_requests
    result = tool_results.last
    assert_equal ["execution_hour"], result["missing_fields"]
    assert_equal "month", @conversation.automation_setup.dig("configuration", "period")

    @question = @conversation.ai_messages.create!(role: "user", content: "às 8h")
    @conversation.update!(request_token: "step-2", requested_at: Time.current)
    @requests.clear
    responses = [call("configure_automation", { configuration: { execution_hour: 8 } }),
      call("prepare_automation", {}), output("Confira a regra abaixo e confirme para salvá-la pausada.")]
    without_business_writes do
      assert_difference "AiActionRequest.count", 1 do
        with_provider(responses) { AiAssistantJob.perform_now(@conversation.id, "step-2", @question.id) }
      end
    end
    assert_nil @conversation.reload.error_message
    initial = JSON.parse(@requests.first["input"].first["content"].first["text"])
    assert_equal "month", initial.dig("automation_setup", "configuration", "period")
    assert_match(/um passo por vez/, @requests.first["system_instruction"])
    names = @requests.first["tools"].pluck("name")
    assert_includes names, "automation_options"
    assert_includes names, "configure_automation"
    assert_includes names, "prepare_automation"
    request = @conversation.ai_action_requests.sole
    assert_equal "create_automation", request.kind
    assert_equal 8, request.payload["execution_hour"]
    assert_equal "sum", request.payload["operation"]
    refute @requests.any? { |payload| payload.to_json.include?(request.confirmation_token) }
    assert @requests.all? { |payload| payload["store"] == false }
  end

  test "missing source data is returned as unavailable rather than a usable zero" do
    response = AiAssistant::Tools.new(@owner).call("prepare_automation", { configuration: {
      name: "Sem dados", source_key: "invoices", operation: "sum", period: "month", filters: {},
      action_key: "update_indicator", action_config: { routine_template_id: @template.id, routine_indicator_id: @indicator.id },
      schedule: "daily", execution_hour: 8
    } })
    assert response[:confirmation_required]
    assert_equal false, response[:simulation][:available]
    refute response[:simulation].key?(:value)
  end

  test "a complete plain text request can produce a draft in one answer without a wizard interview" do
    text = "Todo dia às 8h, some os gastos de Abastecimento do mês e preencha Despesa mensal no modelo Automação teste. Deixe a regra ativa."
    @question.update!(content: text)
    responses = [
      { steps: [
        { type: "function_call", id: "categories", name: "automation_options", arguments: { group: "categories", query: "Abastecimento" } },
        { type: "function_call", id: "templates", name: "automation_options", arguments: { group: "templates", query: "Automação teste" } }
      ] },
      call("automation_options", { group: "indicators", template_id: @template.id }),
      call("prepare_automation", { configuration: {
        name: "Despesas mensais no GEROT", source_key: "invoices", operation: "sum", period: "month",
        filters: { budget_category_id: @category.id }, action_key: "update_indicator",
        action_config: { routine_template_id: @template.id, routine_indicator_id: @indicator.id },
        schedule: "daily", execution_hour: 8, activate: true
      } }),
      output("Preparei a regra com os dados da sua descrição. Confira a prévia para salvar e ativar.")
    ]
    without_business_writes do
      assert_difference "AiActionRequest.count", 1 do
        with_provider(responses) { AiAssistantJob.perform_now(@conversation.id, "step-1", @question.id) }
      end
    end
    assert_nil @conversation.reload.error_message
    assert_empty @conversation.automation_setup
    initial = JSON.parse(@requests.first["input"].first["content"].first["text"])
    assert_equal text, initial["question"]
    assert_match(/UM TEXTO/, @requests.first["system_instruction"])
    action = @conversation.ai_action_requests.sole
    assert_equal "create_automation", action.kind
    assert_equal true, action.payload["activate"]
    assert_equal "Salvar e ativar automação", action.preview["confirmation_label"]
    assert_equal "pending", action.status
    refute @requests.any? { |payload| payload.to_json.include?(action.confirmation_token) }
    assert tool_results.all? { |result| result["error"].nil? }
  end

  test "a maintenance package from plain text produces one rule with all requested categories" do
    @category.update!(name: "Manutenção caminhões")
    second = BudgetCategory.create!(name: "Manutenção empilhadeiras", sector: :frota)
    create_automation_expense(100)
    create_automation_expense(200, category: second)
    @question.update!(content: "Some manutenção de caminhões e empilhadeiras do mês e atualize Despesa mensal no modelo Automação teste todo dia às 8h.")
    responses = [
      call("automation_options", { group: "categories", query: "Manutenção" }),
      call("prepare_automation", { configuration: {
        name: "Pacote Manutenção", source_key: "invoices", operation: "sum", period: "month",
        filters: { budget_category_ids: [@category.id, second.id] }, action_key: "update_indicator",
        action_config: { routine_template_id: @template.id, routine_indicator_id: @indicator.id }, schedule: "daily", execution_hour: 8
      } }),
      output("O pacote reúne as duas categorias. Confira a prévia para confirmar.")
    ]
    without_business_writes do
      assert_difference "AiActionRequest.count", 1 do
        with_provider(responses) { AiAssistantJob.perform_now(@conversation.id, "step-1", @question.id) }
      end
    end
    assert_nil @conversation.reload.error_message
    assert_equal [@category.id, second.id].sort.map(&:to_s), @conversation.ai_action_requests.sole.payload.dig("filters", "budget_category_ids")
    assert_equal "300.0", tool_results.last.dig("simulation", "value")
    assert_match(/VÁRIAS categorias/, @requests.first["system_instruction"])
  end

  private

  def call(name, arguments)
    { steps: [{ type: "function_call", id: SecureRandom.hex(4), name: name, arguments: arguments }] }
  end

  def output(text)
    { steps: [{ type: "model_output", content: [{ type: "text", text: text }] }] }
  end

  def tool_results
    @requests.last.fetch("input").select { |item| item["type"] == "function_result" }.map { |item| JSON.parse(item["result"].first["text"]) }
  end

  def without_business_writes(&block)
    assert_no_difference ["AutomationRule.count", "AutomationRun.count", "Task.count", "RoutineValue.count", "Notification.count"], &block
  end

  def with_provider(responses)
    previous = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-automation-key"
    post = lambda do |_url, &block|
      request = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new)
      block.call(request)
      @requests << JSON.parse(request.body)
      Faraday::Response.new(status: 200, body: responses.shift.to_json)
    end
    Faraday.stub(:post, post) { yield }
  ensure
    ENV["GEMINI_API_KEY"] = previous
  end
end
