require 'test_helper'

class AiAssistantAnalyticsTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 22, 12)
    @user = users(:one)
    @user.update!(role: :user, sector: :fleet)
    @tools = AiAssistant::Tools.new(@user)
  end

  teardown { travel_back }

  test 'monthly fleet averages use all saved elapsed days and historical plate eligibility' do
    plates(:two).update_columns(active: false, retired_at: Date.new(2026, 10, 2))
    first = snapshot('2026-10-01', target: 2)
    add_item(first, plates(:one), :available, position: 0)
    add_item(first, plates(:two), :available, position: 1)
    second = snapshot('2026-10-02', target: 2)
    add_item(second, plates(:one), :unavailable, reason: :maintenance)
    add_item(second, plates(:two), :available, position: 0)
    snapshot('2026-10-03', target: 2) # Saved empty snapshot, unlike a missing date.
    fourth = snapshot('2026-10-04', target: 1, special_routes: { 'as' => 1 })
    add_item(fourth, plates(:one), :special_route, special_route: 'as')
    spare = Plate.create!(placa: 'ANALYTICS', setor: 'ROTA', tipo: 'Caminhão')
    add_item(fourth, spare, :exchange, position: 2)
    future = snapshot('2026-10-23', target: 50)
    add_item(future, plates(:one), :available, position: 0)
    snapshot('2026-09-30', target: 99)

    result = @tools.call('fleet_analysis', { month: '2026-10' })
    assert result[:available]
    assert result[:partial]
    assert_equal Date.new(2026, 10, 22), result[:observed_until]
    assert_equal 31, result[:calendar_days]
    assert_equal 4, result[:recorded_days]
    assert_equal 18, result[:missing_days]
    assert_equal 9, result[:future_days]
    assert_equal 0.5, result[:averages]['available']
    assert_equal 0.25, result[:averages]['exchange']
    assert_equal 0.25, result[:averages]['unavailable']
    assert_equal 0.25, result[:averages]['special_route']
    assert_equal 1.25, result[:averages]['fleet_total']
    assert_equal 1.75, result[:averages]['agreed_quantity']
    assert_equal 3, result[:days_below_target]
    assert_equal 5, result[:shortfall_vehicle_days]
    assert_equal 0, result[:minimum_available][:count]
    assert_equal 2, result[:maximum_available][:count]
    assert_equal({ 'Manutenção' => 1 }, result[:unavailable_reasons_vehicle_days])
    assert_equal [first.date, second.date, Date.new(2026, 10, 3), fourth.date], result[:daily][:records].pluck(:date)
    assert @tools.sources.any? { |source| source[:path].include?('fleet_availabilities') }
  end

  test 'fleet aggregates are independent of daily pagination and accept explicit intervals' do
    (1..21).each do |day|
      fleet = snapshot(Date.new(2026, 10, day), target: 1)
      add_item(fleet, plates(:one), day == 21 ? :unavailable : :available, position: 0)
    end
    first = @tools.call('fleet_analysis', { month: '2026-10' })
    second = @tools.call('fleet_analysis', { month: '2026-10', page: 2 })
    assert_equal 0.95, first[:averages]['available']
    assert_equal first[:averages], second[:averages]
    assert_equal 21, first[:daily][:total]
    assert first[:daily][:has_more]
    assert_equal 1, second[:daily][:records].size
    refute second[:daily][:has_more]
    range = @tools.call('fleet_analysis', { from: '2026-10-20', to: '2026-10-21' })
    assert_equal 0.5, range[:averages]['available']
    refute range[:partial]
  end

  test 'missing and future fleet periods cannot become zero averages' do
    %w[2026-09 2026-11].each do |month|
      result = @tools.call('fleet_analysis', { month: month })
      refute result[:available]
      assert_nil result[:averages]
      assert_equal 0, result[:recorded_days]
    end
    result = @tools.call('fleet_analysis', { month: '2026-11' })
    assert_nil result[:observed_until]
    assert_equal 0, result[:missing_days]
    assert_equal 30, result[:future_days]
  end

  test 'finance analysis ranks goal deviations and scoped contributors without adding overlapping budgets' do
    maintenance = category('Manutenção analítica')
    parts = category('Peças analíticas')
    uncovered = category('Despesa sem meta')
    highest = invoice('MAINT-700', maintenance, 700)
    invoice('PARTS-300', parts, 300)
    invoice('UNCOVERED-200', uncovered, 200)
    invoice('PREVIOUS-400', maintenance, 400, date: '2026-08-31')
    invoice('NEXT-999', maintenance, 999, date: '2026-10-01')
    goal('Manutenção consolidada', [maintenance, parts], 800)
    goal('Manutenção sobreposta', [maintenance], 500)
    goal('Peças dentro da meta', [parts], 600)
    other_user = users(:two)
    other_user.update!(sector: :finance)
    secret = category('Financeiro reservado', sector: :financeiro)
    invoice('SECRET-9999', secret, 9999, purchaser: other_user)
    goal('Meta reservada', [secret], 100, sector: :financeiro)

    result = @tools.call('financial_analysis', { month: '2026-09' })
    assert_equal '2026-09', result[:month]
    assert_equal ['frota'], result[:sectors]
    refute result[:partial]
    assert_equal 3, result[:invoices]
    assert_equal 1200, result[:total_amount]
    assert_equal 400, result[:previous_month][:total_amount]
    assert_equal 800, result[:previous_month][:change_amount]
    assert_equal 200, result[:previous_month][:change_percentage]
    assert_equal({ total: 3, over_target: 2, within_target: 1 }, result[:goal_counts])
    rows = result[:goals][:records]
    assert_equal ['Manutenção consolidada', 'Manutenção sobreposta', 'Peças dentro da meta'], rows.pluck(:name)
    assert_equal [1000, 700, 300], rows.pluck(:spent)
    assert_equal [200, 200, 0], rows.pluck(:excess)
    assert_equal [-200, -200, 300], rows.pluck(:remaining)
    assert_equal [125, 140, 50], rows.pluck(:percentage)
    assert_equal 200, result[:spending_without_goal]
    assert_equal 700, rows.first[:top_suppliers].first[:spent]
    assert_equal highest.id, rows.first[:largest_invoices].first[:id]
    assert_equal [700, 300], rows.first[:categories].pluck(:spent)
    assert_equal 300, result[:categories][:records].first[:change_amount]
    refute_includes result.to_json, 'SECRET'
    refute_includes result.to_json, 'reservada'
    assert @tools.sources.none? { |source| source[:label].include?('SECRET') }
    assert_includes @tools.sources.first[:path], 'month=9'
    assert_includes @tools.sources.first[:path], 'year=2026'
  end

  test 'finance accounts and admins use all authorized sectors unless explicitly filtered' do
    fleet_category = category('Frota análise')
    invoice('FLEET-100', fleet_category, 100)
    other_user = users(:two)
    other_user.update!(sector: :finance)
    finance_category = category('Financeiro análise', sector: :financeiro)
    invoice('FIN-200', finance_category, 200, purchaser: other_user)
    goal('Meta financeira', [finance_category], 150, sector: :financeiro)
    assert_equal 0, @tools.call('financial_analysis', { month: '2026-09', sector: 'financeiro' })[:invoices]
    @user.update!(sector: :finance)
    assert_equal 300, @tools.call('financial_analysis', { month: '2026-09' })[:total_amount]
    filtered = @tools.call('financial_analysis', { month: '2026-09', sector: 'FINANCEIRO' })
    assert_equal 200, filtered[:total_amount]
    assert_equal ['financeiro'], filtered[:sectors]
    assert_equal 50, filtered[:goals][:records].sole[:excess]
    @user.update!(sector: :warehouse, role: :admin)
    assert_equal 300, @tools.call('financial_analysis', { month: '2026-09' })[:total_amount]
  end

  test 'spending without goals is still analyzable and absent previous data is not a zero baseline' do
    invoice('SPEND-NO-GOAL', category('Sem orçamento'), 350)
    result = @tools.call('financial_analysis', { month: '2026-09' })
    assert result[:has_invoices]
    refute result[:has_goals]
    assert_equal 350, result[:total_amount]
    assert_equal 350, result[:spending_without_goal]
    assert_equal 350, result[:top_suppliers].sole[:spent]
    assert_nil result[:previous_month][:total_amount]
    assert_nil result[:previous_month][:change_percentage]
    assert_empty result[:goals][:records]
    assert_equal 350, @tools.call('financial_summary', { month: '2026-09' })[:total_amount]
    assert_equal 1, @tools.call('list_invoices', { month: '2026-09' })[:total]
    assert_equal 0, @tools.call('financial_summary', {})[:total_amount]
    assert_equal 0, @tools.call('list_invoices', { month: '2026-09', due_from: '2026-09-01', due_until: '2026-09-30' })[:total]
  end

  test 'goals without invoices remain visible and goals from other months are never reused' do
    item = category('Aguardando lançamento')
    goal('Orçamento setembro', [item], 500)
    result = @tools.call('financial_analysis', { month: '2026-09' })
    refute result[:has_invoices]
    assert result[:has_goals]
    assert_equal 500, result[:goals][:records].sole[:remaining]
    assert_empty result[:largest_invoices]
    next_month = @tools.call('financial_analysis', { month: '2026-10' })
    refute next_month[:has_invoices]
    refute next_month[:has_goals]
  end

  test 'goal pagination preserves full counts ranks and uncovered spending' do
    item = category('Meta paginada')
    invoice('PAGE-SPEND', item, 100)
    21.times { |index| goal("Meta #{index}", [item], 50 + index) }
    first = @tools.call('financial_analysis', { month: '2026-09' })
    second = @tools.call('financial_analysis', { month: '2026-09', page: 2 })
    assert_equal({ total: 21, over_target: 21, within_target: 0 }, second[:goal_counts])
    assert_equal 100, second[:total_amount]
    assert_equal 0, second[:spending_without_goal]
    assert_equal 50, first[:goals][:records].first[:excess]
    assert_equal 30, second[:goals][:records].sole[:excess]
    assert first[:goals][:has_more]
    refute second[:goals][:has_more]
  end

  test 'invalid analytical periods and direct calls cannot bypass permissions' do
    %w[fleet_analysis financial_analysis financial_summary list_invoices].each do |name|
      assert @tools.call(name, { month: '2026-13' })[:error], name
      assert @tools.call(name, { month: '1999-01' })[:error], name
    end
    assert @tools.call('fleet_analysis', { from: '2026-10-31', to: '2026-10-01' })[:error]
    assert @tools.call('fleet_analysis', { from: '2024-01-01', to: '2026-10-01' })[:error]
    assert @tools.call('financial_analysis', { sector: 'unknown' })[:error]
    @user.update!(sector: :finance)
    refute_includes @tools.declarations.pluck(:name), 'fleet_analysis'
    assert @tools.call('fleet_analysis', {})[:error]
    @user.update!(sector: :warehouse)
    %w[fleet_analysis financial_analysis].each do |name|
      refute_includes @tools.declarations.pluck(:name), name
      assert @tools.call(name, {})[:error]
    end
    @user.update!(role: :mechanical, sector: :fleet)
    %w[fleet_analysis financial_analysis].each { |name| assert @tools.call(name, {})[:error] }
  end

  private

  def snapshot(date, target:, special_routes: {})
    FleetAvailability.create!(date: date, user: @user, agreed_quantity: target, special_routes: special_routes)
  end

  def add_item(fleet, plate, status, position: 1, **attributes)
    FleetAvailabilityItem.create!(fleet_availability: fleet, plate: plate, status: status, position: position, **attributes)
  end

  def category(name, sector: :frota)
    BudgetCategory.create!(name: name, sector: sector)
  end

  def invoice(code, category, amount, date: '2026-09-15', purchaser: @user)
    supplier = Supplier.create!(name: "Fornecedor #{code}", cnpj: "123#{Supplier.count.to_s.rjust(11, '0')}")
    Invoice.create!(code: code, budget_category: category, supplier: supplier, purchaser: purchaser,
      date_issued: date, due_date: '2026-10-10',
      invoice_numbers_attributes: [{ number: code, amount: amount,
        cost_center: CostCenter.create!(name: "Centro #{code}", sector: category.sector) }])
  end

  def goal(name, categories, target, sector: :frota)
    InvoiceGoal.create!(name: name, budget_categories: categories, target_amount: target,
      sector: sector, reference_month: '2026-09')
  end
end
