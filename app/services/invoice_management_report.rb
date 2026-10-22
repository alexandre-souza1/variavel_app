class InvoiceManagementReport
  class InvalidPeriod < ArgumentError; end
  class InvalidFilter < ArgumentError; end
  class Forbidden < StandardError; end

  include ActionView::Helpers::NumberHelper

  attr_reader :from, :to, :sectors, :cost_center

  def initialize(user:, month:, year:, sector: nil, cost_center_id: nil)
    unless month.to_s.match?(/\A\d{1,2}\z/) && year.to_s.match?(/\A\d{4}\z/) &&
        (1..12).cover?(month.to_i) && (2000..2100).cover?(year.to_i)
      raise InvalidPeriod, 'Selecione mês e ano válidos antes de gerar o relatório financeiro.'
    end
    @from = Date.new(year.to_i, month.to_i, 1)
    @to = from.end_of_month
    raise Forbidden unless user.active? && AiAssistant::Access.new(user).allowed?(:finance)

    @sectors = user.admin? || user.sector_finance? ? BudgetCategory.sectors.keys : user.budget_sectors
    if sector.present?
      selected = BudgetCategory.sectors.key(sector) || (BudgetCategory.sectors.key?(sector) && sector)
      raise Forbidden unless selected && sectors.include?(selected)
      @sectors = [selected]
    end
    scope = Invoice.visible_to(user).joins(:budget_category).where(budget_categories: { sector: sectors })
    if cost_center_id.present?
      raise InvalidFilter, 'Centro de custo inválido.' unless cost_center_id.to_s.match?(/\A[1-9]\d*\z/)
      centers = user.admin? || user.sector_finance? ? CostCenter.all : CostCenter.where(
        id: InvoiceNumber.where(invoice_id: scope.select('invoices.id')).select(:cost_center_id))
      @cost_center = centers.find(cost_center_id)
      scope = scope.where(id: InvoiceNumber.where(cost_center_id: cost_center.id).select(:invoice_id))
    end
    @current = scope.where(date_issued: from..to)
    @previous = scope.where(date_issued: from.prev_month..from.prev_month.end_of_month)
  end

  def partial?
    to > Date.current
  end

  def scope_label
    sectors.map { |sector| BudgetCategory.sectors.fetch(sector) }.join(', ') +
      (cost_center ? " · Centro de custo: #{cost_center.name}" : '')
  end

  def summary
    @summary ||= comparison(@current, @previous).merge(
      goals: goals.size, exceeded_goals: goals.count { |goal| goal[:excess].positive? },
      spending_without_goal: categories.reject { |row| row[:has_goal] }.sum { |row| row[:spent] })
  end

  def categories
    @categories ||= begin
      current_totals = @current.group(:budget_category_id).sum(:total)
      previous_totals = @previous.group(:budget_category_id).sum(:total)
      covered = goal_records.flat_map(&:budget_category_ids).uniq
      BudgetCategory.where(id: current_totals.keys).map do |category|
        spent = current_totals.fetch(category.id)
        previous = previous_totals[category.id]
        { id: category.id, name: category.name, sector: category.sector, spent: spent,
          share: percentage(spent, current_totals.values.sum), has_goal: covered.include?(category.id),
          previous: previous, change: previous && spent - previous }
      end.sort_by { |row| [-row[:spent], row[:id]] }
    end
  end

  def goals
    @goals ||= goal_records.map do |goal|
      current = @current.where(budget_category_id: goal.budget_category_ids)
      previous = @previous.where(budget_category_id: goal.budget_category_ids)
      values = comparison(current, previous)
      previous_goal = InvoiceGoal.includes(:budget_categories).find_by(
        sector: goal.sector, name: goal.name, reference_month: from.prev_month)
      previous_target = previous_goal&.target_amount if previous_goal && previous_goal.budget_category_ids.sort == goal.budget_category_ids.sort
      values.merge(id: goal.id, name: goal.name, sector: goal.sector, target: goal.target_amount,
        percentage: percentage(values[:spent], goal.target_amount),
        remaining: goal.target_amount - values[:spent], excess: [values[:spent] - goal.target_amount, 0.to_d].max,
        previous_target: previous_target, category_names: goal.budget_categories.map(&:name),
        categories: categories.select { |row| goal.budget_category_ids.include?(row[:id]) },
        suppliers: supplier_rows(current).first(5), invoices: invoice_rows(current, limit: 5),
        cost_centers: center_rows(current).first(5))
    end.sort_by { |row| [-row[:excess], -row[:spent], row[:id]] }
  end

  def suppliers
    @suppliers ||= supplier_rows(@current).first(10)
  end

  def largest_invoices
    @largest_invoices ||= invoice_rows(@current, limit: 20)
  end

  def alerts
    result = []
    result << ['Período parcial', 'O mês ainda não terminou ou é futuro. O gasto é acumulado e a meta é mensal; estar abaixo da meta não comprova atingimento no fechamento. A comparação anterior usa o mês completo e não é normalizada por dias ou volume operacional.'] if partial?
    result << ['Sem lançamentos', 'Não há lançamentos por emissão no mês e nos filtros selecionados. Isso não comprova ausência de despesas ou pagamento.'] if summary[:count].zero?
    result << ['Sem metas no período', "Não há metas para #{from.strftime('%m/%Y')} nos setores selecionados. Gastos e concentração são analisáveis; atingimento e estouro de meta não são calculáveis. Metas de outros meses/anos não foram reutilizadas."] if goals.empty?
    if summary[:spending_without_goal].positive?
      result << ['Gastos sem cobertura de meta', "#{money(summary[:spending_without_goal])} em categorias sem meta no mês. Defina orçamento para avaliar atingimento dessas despesas."]
    end
    result << ['Metas excedidas', "#{summary[:exceeded_goals]} de #{goals.size} metas com gasto lançado acima do valor previsto. Consulte o diagnóstico individual; metas sobrepostas não são somadas."] if summary[:exceeded_goals].positive?
    result << ['Recorte por centro de custo', 'O filtro seleciona notas que contêm o centro de custo e usa o total da nota, como no dashboard. A meta permanece a do setor inteiro; este recorte não representa todo o realizado do setor.'] if cost_center
    result.presence || [['Sem excesso nas metas cadastradas', 'Os lançamentos consultados não ultrapassam as metas deste mês. Revise despesas ainda não lançadas antes de concluir o fechamento.']]
  end

  def assessment(goal)
    result = []
    status = if goal[:excess].positive?
               "Excesso de #{money(goal[:excess])}: #{percent(goal[:percentage])} da meta utilizada."
             elsif goal[:remaining].zero?
               'Meta integralmente consumida, sem saldo.'
             else
               "Saldo de #{money(goal[:remaining])}: #{percent(goal[:percentage])} da meta utilizada."
             end
    result << ['Atingimento', "#{money(goal[:spent])} realizados para #{money(goal[:target])} previstos. #{status}"]
    if goal[:previous_count].positive?
      result << ['Variação do gasto', "Mesmas categorias no mês anterior: #{money(goal[:previous_spent])}. Variação: #{money(goal[:change])}#{goal[:change_percentage] ? " (#{percent(goal[:change_percentage])})" : ''}."]
      if goal[:count].positive?
        volume_effect = (goal[:count] - goal[:previous_count]) * goal[:previous_ticket]
        ticket_effect = goal[:count] * (goal[:ticket] - goal[:previous_ticket])
        result << ['Volume e valor médio', "Lançamentos: #{goal[:previous_count]} → #{goal[:count]}; valor médio: #{money(goal[:previous_ticket])} → #{money(goal[:ticket])}. Decomposição da variação: #{money(volume_effect)} por número de lançamentos e #{money(ticket_effect)} por valor médio. Número de notas não equivale a quantidade física; valor médio não comprova aumento de preço unitário."]
      end
    else
      result << ['Sem base comparável anterior', 'Não há lançamentos nas mesmas categorias no mês anterior. Não é possível atribuir o desvio a aumento de frequência ou valor médio.']
    end
    if goal[:previous_target]
      result << ['Mudança de orçamento', "Meta anterior com as mesmas categorias: #{money(goal[:previous_target])}; atual: #{money(goal[:target])}. Diferença de #{money(goal[:target] - goal[:previous_target])}. Uma redução do orçamento pode pressionar o atingimento mesmo sem aumento do gasto."]
    end
    if (supplier = goal[:suppliers].first)
      result << ['Concentração em fornecedor', "#{supplier[:name]} concentra #{money(supplier[:spent])} (#{percent(percentage(supplier[:spent], goal[:spent]))} do gasto da meta). Conferir composição dos serviços/produtos, recorrência e condições comerciais; concentração não comprova sobrepreço."]
    end
    if goal[:invoices].any?
      top = goal[:invoices].first(3)
      total = top.sum { |invoice| invoice[:total] }
      result << ['Lançamentos de maior impacto', "Os #{top.size} maiores lançamentos somam #{money(total)} (#{percent(percentage(total, goal[:spent]))} do realizado). Conferir os documentos para distinguir compras concentradas, despesas extraordinárias e recorrência; os registros, sozinhos, não comprovam essas causas."]
    end
    result << ['Investigação recomendada', goal[:excess].positive? ?
      "Priorize os documentos de maior valor abaixo. #{investigation_checks(goal)} Valide a competência das notas. Não há metas individuais por fornecedor ou categoria quando o orçamento é agrupado." :
      'Acompanhe o saldo e despesas pendentes de lançamento. Não conclua economia definitiva antes de validar o fechamento.']
    result
  end

  def charts
    [
      { title: 'Maiores gastos por categoria', data: categories.first(10).map { |row| [row[:name], row[:spent]] }, unit: :currency },
      { title: 'Maiores fornecedores', data: suppliers.map { |row| [row[:name], row[:spent]] }, unit: :currency },
      { title: 'Utilização das metas · referência 100%', data: goals.first(10).map { |row| [row[:name], row[:percentage]] }, unit: :percent },
      { title: 'Categorias · variação sobre o mês anterior', data: categories.select { |row| row[:change] }.sort_by { |row| -row[:change].abs }.first(10).map { |row| [row[:name], row[:change]] }, unit: :currency }
    ]
  end

  private

  def investigation_checks(goal)
    names = ActiveSupport::Inflector.transliterate(goal[:category_names].join(' ')).downcase
    checks = []
    checks << 'Combustíveis: conferir litros, preço por litro e, quando disponíveis, quilometragem e consumo, para avaliar maior utilização, preço ou eficiência.' if names.match?(/abastecimento|combustivel/)
    checks << 'Manutenções: separar corretivas e preventivas, verificar serviços repetidos, custo de peças e mão de obra nas ordens de serviço.' if names.include?('manutencao')
    checks << 'Pneus: separar aquisições e recapagens, conferir quantidades, custo unitário e vida útil documentada.' if names.match?(/pneu|recap/)
    checks.presence&.join(' ') || 'Conferir quantidades físicas, preços unitários, frequência das compras e itens extraordinários antes de concluir a causa do desvio.'
  end

  def goal_records
    @goal_records ||= InvoiceGoal.where(reference_month: from, sector: sectors).includes(:budget_categories).order(:sector, :name, :id).to_a
  end

  def comparison(current, previous)
    count, previous_count = current.count, previous.count
    spent, previous_spent = current.sum(:total), previous.sum(:total)
    { count: count, spent: spent, ticket: count.positive? ? spent / count : nil,
      previous_count: previous_count, previous_spent: previous_count.positive? ? previous_spent : nil,
      previous_ticket: previous_count.positive? ? previous_spent / previous_count : nil,
      change: previous_count.positive? ? spent - previous_spent : nil,
      change_percentage: previous_count.positive? ? percentage(spent - previous_spent, previous_spent) : nil }
  end

  def supplier_rows(scope)
    scope.joins(:supplier).group('suppliers.id', 'suppliers.name').sum('invoices.total')
      .map { |(id, name), spent| { id: id, name: name, spent: spent } }.sort_by { |row| [-row[:spent], row[:id]] }
  end

  def center_rows(scope)
    InvoiceNumber.where(invoice_id: scope.select('invoices.id')).joins(:cost_center)
      .group('cost_centers.id', 'cost_centers.name').sum(:amount)
      .map { |(id, name), amount| { id: id, name: name, amount: amount } }.sort_by { |row| [-row[:amount], row[:id]] }
  end

  def invoice_rows(scope, limit:)
    scope.includes(:supplier, :budget_category).order(total: :desc, id: :asc).limit(limit).map do |invoice|
      { id: invoice.id, code: invoice.code, date: invoice.date_issued, supplier: invoice.supplier.name,
        category: invoice.budget_category.name, sector: invoice.budget_category.sector,
        total: invoice.total, notes: invoice.notes.to_s.truncate(500) }
    end
  end

  def percentage(value, denominator)
    (value / denominator * 100).round(2) if denominator.positive?
  end

  def money(value)
    number_to_currency(value, unit: 'R$ ', separator: ',', delimiter: '.')
  end

  def percent(value)
    value ? "#{number_with_precision(value, precision: 2, separator: ',')}%" : 'Sem base'
  end
end
