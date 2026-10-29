module AiAssistant
  module FinancialAnalysis
    private

    def financial_analysis(args)
      month = query_month(args['month'])
      scope = finance_scope(args)
      source('Análise financeira e metas do mês', dashboard_invoices_path(month: month.month, year: month.year, sector: args['sector']))
      current = scope.where(date_issued: month..month.end_of_month)
      previous = scope.where(date_issued: month.prev_month..month.prev_month.end_of_month)
      spent_by_category = current.group(:budget_category_id).sum(:total)
      previous_by_category = previous.group(:budget_category_id).sum(:total)
      total = current.sum(:total)
      previous_total = previous.sum(:total)
      previous_count = previous.count
      goals = financial_goal_scope(args, month).map do |goal|
        spent = goal.budget_category_ids.sum { |id| spent_by_category.fetch(id, 0.to_d) }
        { id: goal.id, name: goal.name, sector: goal.sector, target: goal.target_amount, spent: spent,
          remaining: goal.target_amount - spent, deviation: spent - goal.target_amount,
          excess: [spent - goal.target_amount, 0.to_d].max, percentage: financial_percentage(spent, goal.target_amount),
          category_ids: goal.budget_category_ids }
      end.sort_by { |row| [-row[:excess], -row[:spent], row[:id]] }
      covered_ids = goals.flat_map { |row| row[:category_ids] }.uniq
      categories = BudgetCategory.where(id: spent_by_category.keys).map do |category|
        spent = spent_by_category.fetch(category.id)
        previous_spent = previous_by_category[category.id]
        { id: category.id, name: category.name, sector: category.sector, spent: spent,
          share_percentage: financial_percentage(spent, total), has_goal: covered_ids.include?(category.id),
          previous_spent: previous_spent, change_amount: previous_spent && spent - previous_spent }
      end.sort_by { |row| [-row[:spent], row[:id]] }
      goal_page = array_page(goals, args)
      goal_page[:records] = goal_page[:records].map do |row|
        goal_invoices = current.where(budget_category_id: row[:category_ids])
        row.merge(categories: categories.select { |category| row[:category_ids].include?(category[:id]) }.first(5),
          top_suppliers: financial_top_suppliers(goal_invoices, limit: 5),
          largest_invoices: financial_largest_invoices(goal_invoices, limit: 3))
      end
      { month: month.strftime('%Y-%m'), from: month, to: month.end_of_month,
        sectors: financial_sectors(args), requested_sector: args['sector'].presence,
        scope: 'Todos os setores autorizados, salvo filtro explícito de setor',
        invoices: current.count, total_amount: total, has_invoices: current.exists?, has_goals: goals.any?,
        partial: month.end_of_month > Date.current,
        previous_month: { month: month.prev_month.strftime('%Y-%m'), invoices: previous_count,
          total_amount: previous_count.positive? ? previous_total : nil,
          change_amount: previous_count.positive? ? total - previous_total : nil,
          change_percentage: previous_count.positive? ? financial_percentage(total - previous_total, previous_total) : nil },
        goal_counts: { total: goals.size, over_target: goals.count { |row| row[:excess].positive? },
          within_target: goals.count { |row| row[:excess].zero? } },
        goals: goal_page, categories: array_page(categories, args),
        spending_without_goal: categories.reject { |row| row[:has_goal] }.sum { |row| row[:spent] },
        top_suppliers: financial_top_suppliers(current), largest_invoices: financial_largest_invoices(current),
        basis: 'Mês civil e data de emissão. Valores lançados não comprovam pagamento. Metas são as vigentes no mês solicitado, mesmo quando iniciadas em meses anteriores; ausência de meta não significa ausência de gasto.',
        note: 'Categorias podem participar de várias metas: não some metas, gastos ou excessos entre elas. Fornecedores, categorias e lançamentos são possíveis contribuintes do gasto, não causas comprovadas. Detalhes por meta mostram até 5 categorias, 5 fornecedores e 3 lançamentos; rankings gerais mostram até 10 fornecedores e 10 lançamentos. Totais e contadores consideram todos os registros.' }
    end

    def financial_percentage(amount, denominator)
      (amount / denominator * 100).round(2) if denominator.positive?
    end

    def financial_top_suppliers(scope, limit: 10)
      scope.joins(:supplier).group('suppliers.id', 'suppliers.name')
        .order(Arel.sql('SUM(invoices.total) DESC'), 'suppliers.id').limit(limit).sum('invoices.total')
        .map { |(id, name), spent| { id: id, name: name, spent: spent } }
    end

    def financial_largest_invoices(scope, limit: 10)
      scope.includes(:supplier, :budget_category).order(total: :desc, id: :asc).limit(limit).map { |invoice| invoice_row(invoice) }
    end
  end
end
