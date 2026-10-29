require 'test_helper'
require 'minitest/mock'

class InvoiceManagementReportTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 22, 12)
    @user = users(:one)
    @user.update!(role: :user, sector: :fleet)
  end

  teardown { travel_back }

  test 'recurring goals and budget comparisons use the validity for each month' do
    item = category('Manutenção recorrente')
    original = goal('Orçamento recorrente', [item], 1000, month: '2026-07')
    invoice('RECURRING-300', item, 300)

    report = report_for
    assert_equal original.id, report.goals.sole[:id]
    assert_equal 1000, report.goals.sole[:previous_target]
    assert_equal 700, report.goals.sole[:remaining]

    revision = goal('Orçamento recorrente', [item], 500, month: '2026-09')
    revised_report = report_for
    assert_equal revision.id, revised_report.goals.sole[:id]
    assert_equal 1000, revised_report.goals.sole[:previous_target]
    assert_equal 200, revised_report.goals.sole[:remaining]
    assert_equal original.id, report_for(month: 8).goals.sole[:id]

    revision.update!(ends_at: '2026-10')
    original.update!(ends_at: '2026-08')
    assert_empty report_for(month: 11).goals
  end

  test 'the selected year sector and grouped goal categories determine attainment' do
    truck = category('Manutenção caminhão relatório')
    forklift = category('Manutenção empilhadeira relatório')
    fuel = category('Abastecimento relatório')
    tires = category('Pneu relatório')
    unbudgeted = category('Sem meta relatório')
    invoice('TRUCK-700', truck, 700)
    invoice('TRUCK-300', truck, 300)
    invoice('FORK-200', forklift, 200)
    invoice('FUEL-900', fuel, 900)
    invoice('TIRE-100', tires, 100)
    invoice('OTHER-50', unbudgeted, 50)
    invoice('PREV-TRUCK', truck, 400, date: '2026-08-15')
    invoice('PREV-FORK', forklift, 100, date: '2026-08-16')
    invoice('WRONG-YEAR', truck, 5000, date: '2025-09-15')
    invoice('NEXT-MONTH', truck, 9999, date: '2026-10-01')
    goal('118 - GASTOS COM MANUTENÇÕES', [truck, forklift], 1000)
    goal('118 - GASTOS COM MANUTENÇÕES', [truck, forklift], 1100, month: '2026-08')
    goal('116 - GASTOS COM COMBUSTÍVEIS', [fuel], 800)
    goal('132 - GASTOS COM PNEUS', [tires], 300)

    report = report_for
    assert_equal Date.new(2026, 9, 1), report.from
    assert_equal Date.new(2026, 9, 30), report.to
    assert_equal 2250, report.summary[:spent]
    assert_equal 6, report.summary[:count]
    assert_equal 2, report.summary[:exceeded_goals]
    assert_equal 50, report.summary[:spending_without_goal]
    assert_equal 3, report.goals.size
    maintenance = report.goals.first
    assert_equal '118 - GASTOS COM MANUTENÇÕES', maintenance[:name]
    assert_equal 1200, maintenance[:spent]
    assert_equal 200, maintenance[:excess]
    assert_equal(-200, maintenance[:remaining])
    assert_equal 120, maintenance[:percentage]
    assert_equal [1000, 200], maintenance[:categories].pluck(:spent)
    assert_equal 1100, maintenance[:previous_target]
    assert_equal 500, maintenance[:previous_spent]
    assert_equal 700, maintenance[:change]
    assert_equal 3, maintenance[:count]
    assert_equal 2, maintenance[:previous_count]
    assessment = report.assessment(maintenance).to_h
    assert_includes assessment['Volume e valor médio'], 'R$ 250,00 por número'
    assert_includes assessment['Volume e valor médio'], 'R$ 450,00 por valor médio'
    assert_includes assessment['Mudança de orçamento'], '-R$ 100,00'
    assert_includes assessment['Lançamentos de maior impacto'], '100,00%'
    assert_includes assessment['Investigação recomendada'], 'corretivas e preventivas'
    fuel_goal = report.goals.find { |row| row[:name].start_with?('116') }
    assert_includes report.assessment(fuel_goal).to_h['Investigação recomendada'], 'litros, preço por litro'
    refute_includes report.largest_invoices.pluck(:code), 'WRONG-YEAR'
    refute_includes report.largest_invoices.pluck(:code), 'NEXT-MONTH'
    previous_year = report_for(year: 2025)
    assert_equal 5000, previous_year.summary[:spent]
    assert_empty previous_year.goals
    assert_includes previous_year.alerts.to_h['Sem metas no período'], '09/2025'
  end

  test 'overlapping goals preserve separate comparisons and do not duplicate invoice allocations' do
    item = category('Categoria agrupada')
    entry = invoice('SPLIT-100', item, 40)
    second_center = CostCenter.create!(name: 'Segundo rateio', sector: :frota)
    entry.invoice_numbers.create!(number: 'SECOND-60', amount: 60, cost_center: second_center)
    entry.save!
    goal('Primeira meta', [item], 50)
    goal('Segunda meta', [item], 80)
    report = report_for
    assert_equal 100, report.summary[:spent]
    assert_equal 1, report.summary[:count]
    assert_equal [100, 100], report.goals.pluck(:spent)
    assert_equal [50, 20], report.goals.pluck(:excess)
    assert_equal 0, report.summary[:spending_without_goal]
    assert_equal [60, 40], report.goals.first[:cost_centers].pluck(:amount)
    refute report.summary.key?(:total_target)

    filtered = report_for(cost_center_id: second_center.id)
    assert_equal 100, filtered.summary[:spent]
    assert_equal 1, filtered.summary[:count]
    assert_includes filtered.scope_label, 'Segundo rateio'
    assert_includes filtered.alerts.to_h['Recorte por centro de custo'], 'total da nota'
  end

  test 'missing incomplete malformed and excessive periods are rejected before querying invoices' do
    queries = []
    ActiveSupport::Notifications.subscribed(->(*args) { queries << args.last[:sql] }, 'sql.active_record') do
      [{ month: nil }, { year: nil }, { month: 0 }, { month: 13 }, { month: '9x' },
       { year: '2026x' }, { year: 1999 }, { year: 2101 }].each do |args|
        assert_raises(InvoiceManagementReport::InvalidPeriod) { report_for(**args) }
      end
    end
    refute queries.any? { |sql| sql.match?(/\bFROM "invoices"\b/) }
  end

  test 'unauthorized sectors records and accounts cannot widen the report' do
    item = category('Setor permitido')
    invoice('VISIBLE', item, 100)
    other = users(:two)
    other.update!(sector: :finance)
    secret = category('Setor reservado', sector: :financeiro)
    invoice('SECRET', secret, 900, purchaser: other)
    goal('META SECRET', [secret], 500, sector: :financeiro)
    assert_equal 100, report_for.summary[:spent]
    assert_empty report_for.goals
    assert_raises(InvoiceManagementReport::Forbidden) { report_for(sector: 'financeiro') }
    assert_raises(ActiveRecord::RecordNotFound) { report_for(cost_center_id: Invoice.find_by!(code: 'SECRET').invoice_numbers.first.cost_center_id) }
    @user.update!(sector: :finance)
    assert_equal 1000, report_for.summary[:spent]
    filtered = report_for(sector: 'FINANCEIRO')
    assert_equal 900, filtered.summary[:spent]
    assert_equal 400, filtered.goals.sole[:excess]
    @user.update!(sector: :warehouse, role: :admin)
    assert_equal 1000, report_for.summary[:spent]
    @user.update!(role: :user)
    assert_raises(InvoiceManagementReport::Forbidden) { report_for }
    @user.update!(role: :mechanical, sector: :fleet)
    assert_raises(InvoiceManagementReport::Forbidden) { report_for }
    @user.update!(active: false)
    assert_raises(InvoiceManagementReport::Forbidden) { report_for }
  end

  test 'PDF contains technical analysis without writing records or calling Gemini' do
    item = category('Relatório técnico')
    entry = invoice('REPORT', item, 130)
    entry.update!(notes: 'Serviço em freios e suspensão. Conferir ordem de serviço.')
    goal('Meta técnica', [item], 100)
    report = report_for
    queries = []
    pdf = nil
    ActiveSupport::Notifications.subscribed(->(*args) { queries << args.last[:sql] }, 'sql.active_record') do
      Faraday.stub(:post, ->(*) { flunk 'Financial PDF must not call Gemini' }) do
        pdf = InvoiceManagementPdf.new(report)
        assert pdf.render.start_with?('%PDF-')
      end
    end
    assert_operator pdf.page_count, :>=, 5
    assert_equal 4, report.charts.size
    assert_equal 30, report.goals.sole[:excess]
    assert_equal entry.notes, report.goals.sole[:invoices].sole[:notes]
    refute queries.any? { |sql| sql.match?(/\A\s*(INSERT\s+INTO|UPDATE\s+|DELETE\s+FROM)/i) }
  end

  test 'empty zero and partial periods produce explicit limitations and valid PDFs' do
    report = report_for(month: 10)
    assert report.partial?
    assert_nil report.summary[:previous_spent]
    assert_includes report.alerts.to_h, 'Período parcial'
    assert_includes report.alerts.to_h, 'Sem lançamentos'
    assert_includes report.alerts.to_h, 'Sem metas no período'
    assert InvoiceManagementPdf.new(report).render.start_with?('%PDF-')
    item = category('Base zerada')
    invoice('ZERO-PREV', item, 0, date: '2026-08-01')
    invoice('ZERO-CURRENT', item, 0)
    goal('Meta sem consumo', [item], 100)
    report = report_for
    assert_nil report.summary[:change_percentage]
    assert_equal 0, report.summary[:spent]
    assert_equal 100, report.goals.sole[:remaining]
    assert InvoiceManagementPdf.new(report).render.start_with?('%PDF-')
  end

  private

  def report_for(month: 9, year: 2026, **filters)
    InvoiceManagementReport.new(user: @user, month: month, year: year, **filters)
  end

  def category(name, sector: :frota)
    BudgetCategory.create!(name: name, sector: sector)
  end

  def invoice(code, category, amount, date: '2026-09-15', purchaser: @user)
    supplier = Supplier.create!(name: "Fornecedor #{code}", cnpj: "123#{Supplier.count.to_s.rjust(11, '0')}")
    Invoice.create!(code: code, budget_category: category, supplier: supplier, purchaser: purchaser,
      date_issued: date, due_date: date, invoice_numbers_attributes: [{ number: code, amount: amount,
        cost_center: CostCenter.create!(name: "Centro #{code}", sector: category.sector) }])
  end

  def goal(name, categories, target, month: '2026-09', sector: :frota)
    InvoiceGoal.create!(name: name, budget_categories: categories, target_amount: target,
      sector: sector, reference_month: month)
  end
end
