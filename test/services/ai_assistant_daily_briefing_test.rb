require 'test_helper'
require 'minitest/mock'

class AiAssistantDailyBriefingTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(role: :user, sector: :fleet)
    @tools = AiAssistant::Tools.new(@user)
    TaskAssignment.delete_all
    travel_to Time.current.change(hour: 12, min: 0, sec: 0)
    @today = Date.current
  end

  teardown { travel_back }

  test 'fleet briefing combines personal agenda monthly goal balance vehicle and tire alerts' do
    task = Task.create!(title: 'Revisar freios hoje', bucket: @user.personal_inbox!, creator: @user,
      due_at: @today.in_time_zone.change(hour: 17))
    Task.create!(title: 'Entrada de outro usuário', bucket: users(:two).personal_inbox!, creator: users(:two), due_at: 2.days.ago)
    invoice = create_expense(150)
    InvoiceGoal.create!(name: 'Orçamento manutenção', sector: :frota, reference_month: @today.prev_month,
      target_amount: 200, budget_categories: [invoice.budget_category])
    plates(:one).update_columns(placa: 'ABC1D23', setor: 'ROTA')
    fleet = FleetAvailability.create!(user: @user, date: @today, agreed_quantity: 1)
    FleetAvailabilityItem.create!(fleet_availability: fleet, plate: plates(:one), status: :unavailable,
      reason: :maintenance, observation: 'Freios em revisão', position: 1)
    result = with_tires do
      @tools.call('daily_briefing', {})
    end
    assert_equal @today, result[:date]
    assert_equal 1, result[:personal_tasks][:due_today]
    assert_equal ['Revisar freios hoje'], result[:personal_tasks][:records].pluck(:title)
    refute_includes result.to_json, 'Entrada de outro usuário'
    goal = result[:sections][:finance][:goals][:records].first
    assert_equal 50, goal[:remaining]
    assert_equal false, goal[:exceeded]
    assert_equal 150, result[:sections][:finance][:spent]
    assert_equal 'ABC1D23', result[:sections][:fleet][:unavailable][:records].first[:plate]
    assert_equal 'Freios em revisão', result[:sections][:fleet][:unavailable][:records].first[:observation]
    assert_equal 'FOGO-IA', result[:sections][:tires][:records].first[:fire_number]
    assert_equal 2.5, result[:sections][:tires][:records].first[:smallest_tread_depth]
    refute result[:sections].key?(:people)
    refute result[:sections].key?(:warehouse)
    assert @tools.sources.any? { |source| source[:path].include?('fleet_availabilities') }
    assert @tools.sources.any? { |source| source[:path].include?('invoices') }
  end

  test 'financial headroom stays per goal and shows negative balances without adding overlapping goals' do
    @user.update!(sector: :finance)
    invoice = create_expense(150, sector: :financeiro)
    2.times do |index|
      InvoiceGoal.create!(name: "Meta #{index}", sector: :financeiro, reference_month: @today,
        target_amount: 100, budget_categories: [invoice.budget_category])
    end
    brief = @tools.call('daily_briefing', {})
    finance = brief[:sections][:finance]
    assert_equal 150, finance[:spent]
    assert_equal 2, finance[:exceeded_goals]
    assert_equal [-50, -50], finance[:goals][:records].pluck(:remaining)
    refute finance.key?(:total_remaining)
    refute brief[:sections].key?(:fleet)
    refute brief[:sections].key?(:tires)
    assert_match(/não some os saldos/, finance[:note])
  end

  test 'warehouse summary uses AZ window and does not inherit fleet or financial access' do
    @user.update!(sector: :warehouse)
    brief = @tools.call('daily_briefing', {})
    sections = brief[:sections]
    assert sections.key?(:warehouse)
    assert sections.key?(:people)
    assert sections.key?(:indicators)
    %i[finance fleet tires delivery team_schedule pcd].each { |key| refute sections.key?(key) }
    assert_equal 19, sections[:warehouse][:from].day
    assert_equal 18, sections[:warehouse][:to].day
  end

  test 'today GEROT missing values and deviations are calculated without creating rows' do
    @user.update!(sector: :finance)
    template = RoutineTemplate.create!(name: 'Resumo financeiro IA', sector: :finance)
    category = template.routine_categories.create!(name: 'Indicadores', position: 0)
    indicator = category.routine_indicators.create!(name: 'Meta diária', position: 0, value_type: :decimal, calculation_type: :plus, goal_direction: :greater_or_equal)
    indicator.routine_indicator_targets.create!(goal: '100', starts_at: @today)
    routine = template.routines.create!(created_by: @user, title: 'GEROT do dia', period_start: @today, period_end: @today)
    assert_no_difference 'RoutineValue.count' do
      result = @tools.call('daily_briefing', {})[:sections][:indicators]
      expected = routine.reference_dates_for(indicator).include?(@today) ? 1 : 0
      assert_equal expected, result[:expected_today]
      assert_equal expected, result[:pending_today]
      assert_equal 0, result[:filled_today]
    end
    routine.routine_values.create!(routine_indicator: indicator, reference_date: @today, value: '25')
    result = @tools.call('daily_briefing', {})[:sections][:indicators]
    assert_equal 1, result[:below_goal]
    assert_equal 0, result[:pending_today]
    assert_equal 25, result[:alerts][:records].first[:calculation][:value]
    assert result[:alerts][:records].first[:deviation]
  end

  test 'agenda is private and counts old overdue today and next seven days without duplicating rows' do
    @user.update!(role: :mechanical, sector: :fleet)
    plan = users(:two).action_plans.create!(name: 'Plano da oficina', public: true)
    assigned = Task.create!(title: 'Atribuída', bucket: plan.buckets.first, creator: users(:two), due_at: 2.days.ago)
    assigned.users << @user
    Task.create!(title: 'Não atribuída', bucket: plan.buckets.first, creator: users(:two), due_at: 2.days.ago)
    Task.create!(title: 'Entrada pessoal', bucket: @user.personal_inbox!, creator: @user, due_at: @today.in_time_zone.change(hour: 23))
    future = Task.create!(title: 'Semana seguinte', bucket: plan.buckets.first, creator: users(:two), due_at: @today + 4)
    future.users << @user
    result = @tools.call('daily_briefing', {})
    assert_empty result[:sections]
    agenda = result[:personal_tasks]
    assert_equal 1, agenda[:overdue]
    assert_equal 1, agenda[:due_today]
    assert_equal 1, agenda[:due_next_7_days]
    assert_equal 2, agenda[:total]
    assert_equal ['Atribuída', 'Entrada pessoal'], agenda[:records].pluck(:title)
    refute_includes result.to_json, 'Não atribuída'
  end

  test 'admin can focus any sector and non admins cannot request another sector or all' do
    @user.update!(sector: :finance)
    assert @tools.call('daily_briefing', { sector: 'fleet' })[:error]
    assert @tools.call('daily_briefing', { sector: 'all' })[:error]
    assert @tools.call('daily_briefing', { sector: 'unknown' })[:error]
    @user.update!(role: :admin)
    result = with_tires { @tools.call('daily_briefing', { sector: 'fleet' }) }
    assert result[:sections].key?(:fleet)
    assert result[:sections].key?(:tires)
    refute result[:sections].key?(:warehouse)
  end

  test 'missing fleet registration goals and tire connection are reported as unknown not no problems' do
    result = with_tires(error: :not_configured) { @tools.call('daily_briefing', {}) }
    assert_equal false, result[:sections][:fleet][:available]
    assert_equal false, result[:sections][:tires][:available]
    assert_empty result[:sections][:finance][:goals][:records]
    assert_match(/Sem meta cadastrada/, result[:sections][:finance][:note])
    assert_equal false, result[:sections][:consumption][:complete]
  end

  private

  def with_tires(error: nil)
    client = Minitest::Mock.new
    client.expect(:tires_needing_retread, [{ fire_number: 'FOGO-IA', plate: 'ABC1D23', smallest_tread_depth: 2.5 }])
    client.expect(:error, error)
    result = Prolog::TiresClient.stub(:new, client) { yield }
    client.verify
    result
  end

  def create_expense(amount, sector: :frota)
    category = BudgetCategory.create!(name: "Despesa do dia #{sector}", sector: sector)
    supplier = Supplier.create!(name: 'Fornecedor do dia', cnpj: '12345678000199')
    center = CostCenter.create!(name: 'Centro do dia', sector: sector)
    Invoice.create!(code: 'AI-DAILY', supplier: supplier, purchaser: @user, budget_category: category,
      date_issued: @today, due_date: @today, invoice_numbers_attributes: [{ number: '123', amount: amount, cost_center: center }])
  end
end
