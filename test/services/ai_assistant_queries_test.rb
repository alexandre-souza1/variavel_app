require 'test_helper'
require 'minitest/mock'

class AiAssistantQueriesTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(role: :user, sector: :fleet)
    @tools = AiAssistant::Tools.new(@user)
  end

  test 'declarations and direct calls enforce the sector permission matrix' do
    expected = {
      fleet: %w[financial_summary du_summary fuel_consumption fleet_dimensioning tire_status stress_events list_plates list_routines time_off_team],
      du: %w[list_employees employee_variable employee_feedbacks du_summary fuel_consumption time_off time_off_team pcd_board fleet_dimensioning tire_status list_plates list_routines],
      warehouse: %w[list_employees employee_variable employee_feedbacks az_summary list_routines],
      hr: %w[financial_summary list_employees employee_variable employee_feedbacks du_summary fuel_consumption time_off time_off_team list_routines],
      safety: %w[financial_summary list_employees employee_variable employee_feedbacks du_summary fuel_consumption tire_status stress_events time_off time_off_team list_routines],
      finance: %w[financial_summary list_invoices financial_goals list_suppliers list_routines],
      planning: %w[financial_summary list_employees employee_variable employee_feedbacks du_summary fuel_consumption time_off time_off_team list_routines]
    }
    tested = %w[financial_summary list_employees employee_variable employee_feedbacks du_summary az_summary fuel_consumption time_off pcd_board fleet_dimensioning tire_status stress_events list_plates list_routines time_off_team ai_usage list_accounts]
    User.sectors.each_key do |sector|
      @user.update!(sector: sector)
      tools = AiAssistant::Tools.new(@user)
      names = tools.declarations.pluck(:name)
      tested.each do |name|
        if expected.fetch(sector.to_sym).include?(name)
          assert_includes names, name, "#{sector} permits #{name}"
        else
          refute_includes names, name, "#{sector} denies #{name}"
          assert tools.call(name, {})[:error], "Direct calls must deny #{sector}/#{name}"
        end
      end
    end
    @user.update!(role: :admin, sector: :du)
    assert_equal AiAssistant::Catalog.entries.keys.sort,
      (AiAssistant::Tools.new(@user).declarations.pluck(:name) & AiAssistant::Catalog.entries.keys).sort
  end

  test 'mechanics have assigned tasks own checklists and public resources without sector inheritance' do
    @user.update!(role: :mechanical, sector: :finance)
    names = @tools.declarations.pluck(:name)
    %w[list_tasks list_plans list_documents public_resources list_checklists].each { |name| assert_includes names, name }
    %w[list_invoices employee_details meeting_details routine_details ai_usage fleet_status].each do |name|
      refute_includes names, name
      assert @tools.call(name, {})[:error]
    end
  end

  test 'revoking a permission or disabling a user affects already created tool objects' do
    @user.update!(sector: :finance)
    assert @tools.declarations.any? { |tool| tool[:name] == 'financial_summary' }
    User.where(id: @user.id).update_all(sector: User.sectors[:warehouse])
    assert @tools.call('financial_summary', {})[:error]
    User.where(id: @user.id).update_all(active: false)
    assert @tools.call('navigation', {})[:error]
  end

  test 'finance queries scope details totals searches and cost centers before aggregation' do
    fleet = create_invoice('FROTA-AI', :frota, @user, 100)
    finance_user = users(:two)
    finance_user.update!(sector: :finance)
    other = create_invoice('FINANCE-SECRET', :financeiro, finance_user, 900)
    center = CostCenter.create!(name: 'Oficina IA', sector: :frota)
    fleet.invoice_numbers.update_all(cost_center_id: center.id)
    fleet.invoice_numbers.create!(number: 'EXTRA', amount: 50, cost_center: center)
    fleet.update!(notes: 'Troca de óleo')
    # Two rows for the same center must never duplicate the invoice total.
    result = @tools.call('list_invoices', { cost_center_id: center.id })
    assert_equal 1, result[:total]
    assert_equal 150, result[:amount]
    assert_equal 150, @tools.call('financial_summary', {})[:total_amount]
    assert @tools.call('invoice_details', { invoice_id: other.id })[:error]
    assert_equal 0, @tools.call('list_invoices', { query: 'SECRET', sector: 'financeiro' })[:total]
    details = @tools.call('invoice_details', { invoice_id: fleet.id })
    assert_equal 'Troca de óleo', details[:notes]
    assert_equal 2, details[:allocation][:total]
    assert_equal ['Fornecedor FROTA-AI'], @tools.call('list_suppliers', {})[:records].pluck(:name)
    assert @tools.sources.none? { |item| item[:path] == "/invoices/#{other.id}" }
    @user.update!(sector: :finance)
    assert_equal 1050, @tools.call('financial_summary', {})[:total_amount]
    assert_equal 900, @tools.call('financial_summary', { sector: 'financeiro' })[:total_amount]
    fleet.update_columns(date_issued: 2.months.ago.to_date, due_date: Date.current)
    due = @tools.call('list_invoices', { due_from: Date.current.iso8601, due_until: Date.current.iso8601 })
    assert_equal [fleet.id], due[:records].pluck(:id)
    assert_nil due[:emission_period]
  end

  test 'financial goals use category spend and exclude other sectors' do
    invoice = create_invoice('FROTA-GOAL', :frota, @user, 100)
    goal = InvoiceGoal.create!(name: 'Meta Frota IA', sector: :frota, reference_month: Date.current,
      target_amount: 200, budget_categories: [invoice.budget_category])
    values = @tools.call('financial_goals', {})[:records].find { |row| row[:name] == goal.name }
    assert_equal 100, values[:spent]
    assert_equal 100, values[:remaining]
    assert_equal 50, values[:percentage]
    assert_empty @tools.call('financial_goals', { sector: 'rh' })[:records]
  end

  test 'DU and warehouse directory and details cannot be widened by parameters or direct ids' do
    du = create_employee('Pessoa DU', 'du', 'motorista')
    az = create_employee('Pessoa AZ', 'az', 'operador')
    @user.update!(sector: :du)
    assert_equal [du.id], @tools.call('list_employees', { query: 'Pessoa' })[:records].pluck(:id)
    %w[employee_details employee_variable employee_feedbacks time_off].each do |name|
      assert @tools.call(name, { employee_id: az.id, sector: 'az' })[:error]
    end
    assert @tools.call('list_employees', { sector: 'az' })[:error]
    @user.update!(sector: :warehouse)
    assert_equal [az.id], @tools.call('list_employees', { query: 'Pessoa' })[:records].pluck(:id)
    assert @tools.call('employee_details', { employee_id: du.id })[:error]
    @user.update!(role: :admin, sector: :du)
    assert_equal 2, @tools.call('list_employees', { query: 'Pessoa' })[:total]
    assert_equal az.nome, @tools.call('employee_details', { employee_id: az.id })[:name]
    refute_includes @tools.call('employee_details', { employee_id: du.id }).to_json, 'data_nascimento'
    refute_includes @tools.call('employee_details', { employee_id: du.id }).to_json, 'cpf'
  end

  test 'variable queries preserve saved closings instead of recalculating changed source maps' do
    @user.update!(sector: :du)
    employee = create_employee('Variável IA', 'du', 'motorista')
    closing = VariableClosing.capture!(employee: employee, user: @user, year: Date.current.year, month: Date.current.month, reason: 'Fechamento IA')
    result = @tools.call('employee_variable', { employee_id: employee.id, month: Date.current.strftime('%Y-%m'), sector: 'du' })
    assert_equal closing.revision, result[:revision]
    assert_equal closing.result['totals'], result[:values]['totals']
    refute_includes result.to_json, 'cpf'
    assert_match(/Fechamento registrado/, result[:source])
    @user.update!(sector: :hr)
    assert @tools.call('employee_variable', { employee_id: employee.id })[:error]
    assert_equal employee.nome, @tools.call('employee_variable', { employee_id: employee.id, sector: 'az' })[:name]
  end

  test 'feedback defaults to current year and never substitutes historical feedback' do
    @user.update!(sector: :hr)
    employee = create_employee('Feedback IA', 'du', 'motorista')
    PeopleCycleFeedback.create!(cycle: (Date.current.year - 1).to_s, employee_name: employee.nome,
      employee_key: PeopleCycleFeedback.normalize(employee.nome), profile: 'colaborador', employee_id: employee.id,
      stage: 'Avaliação', response: 'Feedback do ano anterior', imported_by: @user)
    assert_equal 0, @tools.call('employee_feedbacks', { employee_id: employee.id })[:total]
    previous = @tools.call('employee_feedbacks', { employee_id: employee.id, year: Date.current.year - 1 })
    assert_equal 1, previous[:total]
    assert_equal 'Feedback do ano anterior', previous[:records].first[:response]
  end

  test 'plan visibility does not expose private meeting content while collaborators and admins can read' do
    owner = users(:two)
    plan = owner.action_plans.create!(name: 'Plano compartilhado IA', public: true, sector: :fleet)
    meeting = MeetingMinute.new(action_plan: plan, creator: owner, title: 'Ata privada IA', meeting_date: Date.current,
      status: :completed, summary: 'DECISAO_RESTRITA', decisions: ['Decisão'], pending_items: ['Pendência'])
    meeting.save!(validate: false)
    assert_equal 0, @tools.call('list_meetings', { plan_id: plan.id })[:total]
    assert @tools.call('meeting_details', { meeting_id: meeting.id })[:error]
    assert_empty @tools.sources
    meeting.update!(collaborator: @user)
    assert_equal 'DECISAO_RESTRITA', @tools.call('meeting_details', { meeting_id: meeting.id })[:summary]
    @user.update!(role: :admin, sector: :warehouse)
    meeting.update!(collaborator: nil)
    assert_equal 'DECISAO_RESTRITA', @tools.call('meeting_details', { meeting_id: meeting.id })[:summary]
    meeting.update!(decisions: ['x' * 1000])
    excerpt = @tools.call('meeting_details', { meeting_id: meeting.id })
    assert excerpt[:truncated]
    assert_operator excerpt[:decisions].first.length, :<=, 800
  end

  test 'GEROT reads authorized indicators and calculations without generating missing values' do
    own = create_routine('GEROT Frota IA', :fleet)
    other = create_routine('GEROT RH IA', :hr)
    category = own.routine_template.routine_categories.create!(name: 'Indicadores IA', position: 0)
    indicator = category.routine_indicators.create!(name: 'Gasto IA', position: 0, value_type: :decimal, calculation_type: :plus)
    indicator.routine_indicator_targets.create!(goal: '100', starts_at: own.period_start)
    own.routine_values.create!(routine_indicator: indicator, reference_date: own.period_start, value: '25')
    own.reload
    assert_equal [own.id], @tools.call('list_routines', { query: 'IA' })[:records].pluck(:id)
    assert @tools.call('routine_details', { routine_id: other.id })[:error]
    assert_no_difference 'RoutineValue.count' do
      details = @tools.call('routine_details', { routine_id: own.id })
      assert_equal 25, details[:indicators][:records].first[:calculation][:value]
      rows = @tools.call('routine_values', { routine_id: own.id, indicator_id: indicator.id })
      assert_equal ['25'], rows[:records].pluck(:value)
      assert_equal 0, @tools.call('routine_values', { routine_id: own.id, indicator_id: routine_indicators(:two).id })[:total]
    end
  end

  test 'checklist details stay private to their owner except admin and supervisor historical access' do
    mine, other = checklists(:one), checklists(:two)
    mine.update_columns(observation: 'Minha observação')
    other.update_columns(observation: 'Observação de outra conta')
    assert_equal 'Minha observação', @tools.call('checklist_details', { checklist_id: mine.id })[:observation]
    assert @tools.call('checklist_details', { checklist_id: other.id })[:error]
    @user.update!(role: :supervisor)
    assert_equal 'Observação de outra conta', @tools.call('checklist_details', { checklist_id: other.id })[:observation]
  end

  test 'public catalog returns registered metadata without fetching or inventing document content' do
    download = Download.create!(title: 'LUP IA', description: 'Descrição do padrão', category: 'LUP', sector: 'FROTA', url: 'https://drive.google.com/file/d/test')
    result = @tools.call('list_documents', { query: 'LUP IA' })
    assert_equal [download.id], result[:records].pluck(:id)
    assert_match(/não foi lido/, result[:note])
    assert_equal 0, @tools.call('list_documents', { query: '%' })[:total]
    assert @tools.call('public_resources', { resource: 'routes', query: 'Cafelândia' })[:records].any? { |row| row['id'] == 'cafelandia' }
    assert_equal 40, @tools.call('public_resources', { resource: 'parking' })[:total]
  end

  test 'DU AZ and fuel reports use registered data and module closing windows' do
    @user.update!(sector: :du)
    Mapa.create!(mapa: 'IA-MAPA', data: '01/10/2026', matric_motorista: 'NOT-REGISTERED', cx_real: 30, pdv_total: 10, pdv_real: 9, recarga: 'NAO')
    result = @tools.call('du_summary', { month: '2026-10' })
    assert_equal Date.new(2026, 9, 21), result[:from]
    assert_equal Date.new(2026, 10, 20), result[:to]
    assert_equal 30, result[:boxes]
    assert_equal 1, result[:devolution][:returned]
    GasolaSupply.create!(external_id: 'AI-QUERY-FUEL', registration: 'AI', plate: 'TEST', concluded_at: Time.zone.local(2026, 10, 1),
      fuel: 'dieselS10', category: 'veículo', status: 'CONCLUDED', liters: 100, distance: 300, goal: 4)
    fuel = @tools.call('fuel_consumption', { month: '2026-10' })
    assert_equal 3, fuel[:totals][:average]
    assert_equal false, fuel[:totals][:achieved]
    assert_equal false, fuel[:complete]
    @user.update!(sector: :warehouse)
    az = @tools.call('az_summary', { month: '2026-10', turno: 0 })
    assert_equal Date.new(2026, 9, 19), az[:from]
    assert_equal Date.new(2026, 10, 18), az[:to]
    assert az[:indicators].any?
    assert @tools.call('az_summary', { turno: 5 })[:error]
  end

  test 'tires unavailable is not returned as zero and unauthorized calls never reach the integration' do
    client = Minitest::Mock.new
    client.expect(:tires_for_plate, [], ['TEST'])
    client.expect(:error, :not_configured)
    Prolog::TiresClient.stub(:new, client) do
      assert_equal false, @tools.call('tire_status', { plate: 'TEST' })[:available]
    end
    client.verify
    @user.update!(sector: :finance)
    Prolog::TiresClient.stub(:new, -> { flunk 'Unauthorized integration access' }) do
      assert @tools.call('tire_status', {})[:error]
    end
  end

  test 'admin analytics and account queries cannot expose private conversations or credentials' do
    @user.update!(role: :admin)
    users(:two).update!(name: 'Pessoa do relatório')
    AiApiRequest.delete_all
    AiApiRequest.create!(user: users(:two), model: 'gemini-3.6-flash', feature: 'assistant',
      requested_at: Time.current, http_status: 200, duration_ms: 10, credential_fingerprint: AiApiRequest.current_credential_fingerprint)
    conversation = AiConversation.create!(user: users(:two))
    conversation.ai_messages.create!(role: 'user', content: 'PERGUNTA_PRIVADA_IA')
    queries = []
    response = nil
    ActiveSupport::Notifications.subscribed(->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }, 'sql.active_record') do
      response = @tools.call('ai_usage', {}).to_json + @tools.call('list_accounts', {}).to_json
    end
    assert_match users(:two).name, response
    %w[PERGUNTA_PRIVADA_IA encrypted_password credential_fingerprint reset_password_token].each { |secret| refute_includes response, secret }
    refute queries.any? { |query| query.match?(/\bai_messages\b|\bai_conversations\b/) }
    @user.update!(role: :user)
    assert @tools.call('ai_usage', {})[:error]
    assert @tools.call('list_accounts', {})[:error]
  end

  test 'invalid dates filters and unknown operations do not execute changes' do
    assert @tools.call('financial_summary', { from: '2026-12-31', to: '2026-01-01' })[:error]
    assert @tools.call('financial_summary', { from: '2000-01-01', to: '2026-01-01' })[:error]
    assert @tools.call('financial_summary', { sector: 'unknown' })[:error]
    assert @tools.call('routine_details', {})[:error]
    assert @tools.call('public_resources', { resource: 'https://example.test' })[:error]
    assert_no_difference 'Invoice.count' do
      assert @tools.call('delete_invoice', { invoice_id: 1 })[:error]
    end
  end

  test 'all registered queries return bounded serializable data without writing application records' do
    @user.update!(role: :admin)
    employee = create_employee('Consulta sem escrita IA', 'du', 'motorista')
    invoice = create_invoice('READ-ONLY-IA', :frota, @user, 100)
    routine = create_routine('GEROT sem escrita IA', :fleet)
    meeting = MeetingMinute.new(action_plan: action_plans(:one), creator: @user, title: 'Ata sem escrita IA',
      meeting_date: Date.current, status: :completed, summary: 'Resumo')
    meeting.save!(validate: false)
    AiSetting.current
    arguments = {
      'daily_briefing' => { sector: 'finance' },
      'invoice_details' => { invoice_id: invoice.id },
      'employee_details' => { employee_id: employee.id },
      'employee_variable' => { employee_id: employee.id, sector: 'du' },
      'employee_feedbacks' => { employee_id: employee.id },
      'time_off' => { employee_id: employee.id },
      'routine_details' => { routine_id: routine.id },
      'routine_values' => { routine_id: routine.id },
      'meeting_details' => { meeting_id: meeting.id },
      'checklist_details' => { checklist_id: checklists(:one).id },
      'public_resources' => { resource: 'parking' }
    }
    client = Minitest::Mock.new
    client.expect(:tires_needing_retread, [])
    client.expect(:error, nil)
    queries = []
    ActiveSupport::Notifications.subscribed(->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }, 'sql.active_record') do
      Prolog::TiresClient.stub(:new, client) do
        AiAssistant::Catalog.entries.each_key do |name|
          response = @tools.call(name, arguments.fetch(name, {}))
          refute response[:error], "#{name}: #{response[:error]}"
          assert JSON.parse(response.to_json).is_a?(Hash), name
        end
      end
    end
    client.verify
    refute queries.any? { |sql| sql.match?(/\A\s*(INSERT\s+INTO|UPDATE\s+|DELETE\s+FROM|ALTER\s+|DROP\s+)/i) },
      "Assistant queries must not write application records"
  end

  private

  def create_invoice(code, sector, purchaser, amount)
    category = BudgetCategory.create!(name: code, sector: sector)
    supplier = Supplier.create!(name: "Fornecedor #{code}", cnpj: "123#{Supplier.count.to_s.rjust(11, '0')}")
    Invoice.create!(code: code, supplier: supplier, purchaser: purchaser, budget_category: category,
      date_issued: Date.current, due_date: Date.current + 5,
      invoice_numbers_attributes: [{ number: code, amount: amount, cost_center: CostCenter.create!(name: "Centro #{code}", sector: sector) }])
  end

  def create_employee(name, sector, cargo)
    employee = Employee.create!(nome: name, matricula: "AI-#{SecureRandom.hex(4)}", cpf: 'DADO_RESTRITO_CPF', data_nascimento: '1990-01-01')
    employee.change_role!({ sector: sector, cargo: cargo, promax: "CODE-#{employee.id}", turno: sector == 'az' ? 0 : nil,
      starts_on: '2026-01-01', reason: 'Teste IA' }, user: @user)
    employee
  end

  def create_routine(name, sector)
    template = RoutineTemplate.create!(name: name, sector: sector)
    template.routines.create!(title: name, created_by: @user, period_start: Date.current.beginning_of_month, period_end: Date.current.end_of_month)
  end
end
