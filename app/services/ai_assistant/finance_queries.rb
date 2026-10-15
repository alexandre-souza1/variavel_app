module AiAssistant
  module FinanceQueries
    private

    def financial_summary(args)
      first, last = date_range(args)
      scope = finance_scope(args).where(date_issued: first..last)
      source('Dashboard financeiro', dashboard_invoices_path(month: first.month, year: first.year))
      categories = scope.joins(:budget_category).group('budget_categories.name').sum('invoices.total')
      suppliers = scope.joins(:supplier).group('suppliers.name').sum('invoices.total')
      { from: first, to: last, basis: 'Data de emissão; valores lançados, sem comprovar pagamento',
        invoices: scope.count, total_amount: scope.sum(:total), suppliers: scope.distinct.count(:supplier_id),
        categories: categories, top_suppliers: suppliers.sort_by { |_name, total| -total }.first(10).to_h }
    end

    def list_invoices(args)
      first, last = date_range(args)
      by_due_date = args['due_from'].present? || args['due_until'].present?
      filter_emission = !by_due_date || args['from'].present? || args['to'].present?
      scope = finance_scope(args)
      scope = scope.where(date_issued: first..last) if filter_emission
      scope = scope.where(budget_category_id: Integer(args['category_id'])) if args['category_id'].present?
      if args['cost_center_id'].present?
        scope = scope.where(id: InvoiceNumber.where(cost_center_id: Integer(args['cost_center_id'])).select(:invoice_id))
      end
      if args['query'].present?
        scope = scope.joins(:supplier, :budget_category).where(
          'invoices.code ILIKE :q OR suppliers.name ILIKE :q OR budget_categories.name ILIKE :q OR invoices.id IN (SELECT invoice_id FROM invoice_numbers WHERE number ILIKE :q)', q: search_pattern(args['query']))
      end
      if by_due_date
        due_first, due_last = date_range({ 'from' => args['due_from'], 'to' => args['due_until'] })
        scope = scope.where(due_date: due_first..due_last)
      end
      result = paginate(scope.includes(:supplier, :budget_category).order(date_issued: :desc, id: :desc), args)
      result[:amount] = scope.sum(:total)
      result[:emission_period] = { from: first, to: last } if filter_emission
      result[:due_period] = { from: due_first, to: due_last } if by_due_date
      result[:basis] = 'Filtros de emissão e/ou vencimento indicados no resultado. Vencimento não comprova pagamento ou atraso financeiro.'
      result[:records] = result[:records].map { |invoice| invoice_row(invoice) }
      result
    end

    def invoice_row(invoice)
      source("Lançamento #{invoice.code.presence || invoice.id}", invoice_path(invoice))
      { id: invoice.id, code: invoice.code, supplier: invoice.supplier.name, category: invoice.budget_category.name,
        sector: invoice.budget_category.sector, issued_at: invoice.date_issued, due_date: invoice.due_date, total: invoice.total }
    end

    def invoice_details(args)
      invoice = @access.invoices.includes(:supplier, :budget_category, :purchaser, invoice_numbers: :cost_center).find(Integer(args.fetch('invoice_id')))
      numbers = invoice.invoice_numbers.order(:id)
      page = array_page(numbers.to_a, args)
      page[:records] = page[:records].map { |number| { number: number.number, amount: number.amount, cost_center: number.cost_center&.name } }
      invoice_row(invoice).merge(purchaser: invoice.purchaser&.name, notes: bounded_text(invoice.notes), allocation: page)
    end

    def financial_goals(args)
      month = query_month(args['month'])
      scope = finance_scope(args)
      sectors = @user.admin? || @user.sector_finance? ? BudgetCategory.sectors.keys : @user.budget_sectors
      sectors &= [BudgetCategory.sectors.key(args['sector']) || args['sector']] if args['sector'].present?
      goals = InvoiceGoal.where(reference_month: month, sector: sectors).includes(:budget_categories).order(:sector, :name, :id)
      result = paginate(goals, args)
      result[:month] = month.strftime('%Y-%m')
      result[:records] = result[:records].map do |goal|
        spent = scope.where(date_issued: month..month.end_of_month, budget_category_id: goal.budget_category_ids).sum(:total)
        { name: goal.name, sector: goal.sector, target: goal.target_amount, spent: spent,
          remaining: goal.target_amount - spent, percentage: (spent / goal.target_amount * 100).round(2) }
      end
      source('Metas e gastos do mês', dashboard_invoices_path(month: month.month, year: month.year))
      result
    end

    def list_suppliers(args)
      first, last = date_range(args)
      invoices = @access.invoices.where(date_issued: first..last)
      suppliers = Supplier.where(id: invoices.select(:supplier_id))
      suppliers = suppliers.where('name ILIKE ?', search_pattern(args['query'])) if args['query'].present?
      result = paginate(suppliers.order(:name, :id), args)
      totals = invoices.where(supplier_id: result[:records].map(&:id)).group(:supplier_id).sum(:total)
      result[:records] = result[:records].map do |supplier|
        source(supplier.name, invoices_path(supplier_name: supplier.name))
        { id: supplier.id, name: supplier.name, total_in_period: totals[supplier.id] }
      end
      result.merge(from: first, to: last)
    end

    def financial_catalog(args)
      all_sectors = @user.admin? || @user.sector_finance?
      categories = all_sectors ? BudgetCategory.all : BudgetCategory.where(sector: @user.budget_sectors)
      centers = all_sectors ? CostCenter.all : CostCenter.where(id: InvoiceNumber.where(invoice_id: @access.invoices.select(:id)).select(:cost_center_id))
      if args['query'].present?
        categories = categories.where('name ILIKE ?', search_pattern(args['query']))
        centers = centers.where('name ILIKE ?', search_pattern(args['query']))
      end
      result = { categories: paginate(categories.order(:name, :id), args), cost_centers: paginate(centers.order(:name, :id), args) }
      result.each_value { |group| group[:records] = group[:records].map { |record| { id: record.id, name: record.name, sector: record.sector } } }
      source('Filtros financeiros', invoices_path)
      result
    end
  end
end
