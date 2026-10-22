require 'test_helper'
require 'minitest/mock'

class AiAssistantAnalyticsJobTest < ActiveJob::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 22, 12)
    @user = users(:one)
    @user.update!(role: :user, sector: :fleet)
    @conversation = AiConversation.create!(user: @user, request_token: 'analytics-1', requested_at: Time.current)
  end

  teardown { travel_back }

  test 'the monthly fleet question sends complete analytical results back to the provider' do
    fleet = FleetAvailability.create!(user: @user, date: '2026-10-01', agreed_quantity: 1)
    FleetAvailabilityItem.create!(fleet_availability: fleet, plate: plates(:one), status: :available, position: 0)
    requests = answer_with_tool('Vc consegue me dizer a media de carros disponíveis no mês de outubro?',
      'fleet_analysis', { month: '2026-10' })
    declaration = requests.first['tools'].find { |tool| tool['name'] == 'fleet_analysis' }
    assert declaration['parameters']['properties'].key?('month')
    result = provider_result(requests)
    assert_equal '2026-10-01', result['from']
    assert_equal '2026-10-31', result['to']
    assert_equal 1, result['averages']['available']
    assert_equal 1, result['recorded_days']
    assert_equal 21, result['missing_days']
    assert_equal 9, result['future_days']
    assert_includes requests.first['system_instruction'], 'fleet_status consulta apenas uma data'
    assert @conversation.ai_messages.last.sources.any? { |source| source['path'].include?('fleet_availabilities') }
  end

  test 'the finance question sends September spend goals and contributors back to the provider' do
    category = BudgetCategory.create!(name: 'Manutenção teste IA', sector: :frota)
    supplier = Supplier.create!(name: 'Oficina teste IA', cnpj: '12345678000195')
    center = CostCenter.create!(name: 'Centro teste IA', sector: :frota)
    invoice = Invoice.create!(code: 'ANALYSIS-JOB', budget_category: category, supplier: supplier, purchaser: @user,
      date_issued: '2026-09-15', due_date: '2026-10-10',
      invoice_numbers_attributes: [{ number: 'ANALYSIS-JOB', amount: 130, cost_center: center }])
    InvoiceGoal.create!(name: 'Meta teste IA', reference_month: '2026-09', sector: :frota,
      target_amount: 100, budget_categories: [category])
    requests = answer_with_tool('Consegue me passar um panorama do financeiro do mês de setembro, pra eu saber com o que gastei mais comparado a meta e quais foram meus possiveis ofensores?',
      'financial_analysis', { month: '2026-09' })
    result = provider_result(requests)
    assert_equal '2026-09', result['month']
    assert_equal '130.0', result['total_amount']
    assert_equal 1, result['goal_counts']['over_target']
    assert_equal '30.0', result['goals']['records'].sole['excess']
    assert_equal 'Oficina teste IA', result['top_suppliers'].sole['name']
    assert_equal invoice.id, result['largest_invoices'].sole['id']
    assert_includes requests.first['system_instruction'], 'Sem metas, ainda apresente os gastos'
    assert @conversation.ai_messages.last.sources.any? { |source| source['path'].include?('month=9') }
  end

  private

  def answer_with_tool(question, name, arguments)
    message = @conversation.ai_messages.create!(role: 'user', content: question)
    requests = []
    responses = [
      { steps: [{ type: 'function_call', id: 'analysis-call', name: name, arguments: arguments }] },
      { steps: [{ type: 'model_output', content: [{ type: 'text', text: 'Análise do período solicitado.' }] }] }
    ]
    post = lambda do |_url, &block|
      request = Struct.new(:headers, :options, :body).new({}, Struct.new(:timeout, :open_timeout).new)
      block.call(request)
      requests << JSON.parse(request.body)
      Faraday::Response.new(status: 200, body: responses.shift.to_json)
    end
    previous = ENV['GEMINI_API_KEY']
    ENV['GEMINI_API_KEY'] = 'test-key'
    assert_no_difference ['Invoice.count', 'InvoiceGoal.count', 'FleetAvailability.count', 'FleetAvailabilityItem.count', 'AiActionRequest.count'] do
      Faraday.stub(:post, post) { AiAssistantJob.perform_now(@conversation.id, 'analytics-1', message.id) }
    end
    assert_nil @conversation.reload.error_message
    assert_equal 'Análise do período solicitado.', @conversation.ai_messages.last.content
    requests
  ensure
    ENV['GEMINI_API_KEY'] = previous
  end

  def provider_result(requests)
    JSON.parse(requests.last['input'].last['result'].first['text'])
  end
end
