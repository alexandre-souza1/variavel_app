class InvoicesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_invoice, only: %i[ show edit update destroy download_document ]
  before_action :set_purchasers, only: [:new, :edit, :create, :update]

  # GET /invoices or /invoices.json
  def index
    prepare_invoice_sector_filter
    @invoices = Invoice.with_attached_documents
                       .includes(:supplier, :budget_category, invoice_numbers: :cost_center)
                       .all

    @invoices = apply_invoice_sector_filter(@invoices)

    # filtro por categoria orçamentária
    @invoices = @invoices.where(budget_category_id: params[:budget_category_id]) if params[:budget_category_id].present?

    # filtro por categoria orçamentária
    if params[:cost_center_id].present?
      @invoices = @invoices.joins(:invoice_numbers)
                          .where(invoice_numbers: { cost_center_id: params[:cost_center_id] })
                          .distinct
    end

    # filtro por ID da invoice
    @invoices = @invoices.where(id: params[:id]) if params[:id].present?

    # filtro por CNPJ do fornecedor
    if params[:supplier_cnpj].present?
      @invoices = @invoices.joins(:supplier)
                          .where("suppliers.cnpj LIKE ?", "%#{params[:supplier_cnpj]}%")
    end

    # filtro por nome do fornecedor
    if params[:supplier_name].present?
      name = params[:supplier_name].strip
      @invoices = @invoices.joins(:supplier)
                          .where("suppliers.name ILIKE ?", "%#{name}%")
    end

    # filtro por data de emissão
    @invoices = @invoices.where(date_issued: params[:date_issued]) if params[:date_issued].present?

    # filtro por data de vencimento
    @invoices = @invoices.where(due_date: params[:due_date]) if params[:due_date].present?

    # filtro por total
    @invoices = @invoices.where(total: params[:total]) if params[:total].present?

    # filtro por número de nota fiscal (invoice_numbers)
    if params[:invoice_number].present?
      @invoices = @invoices.joins(:invoice_numbers)
                          .where("invoice_numbers.number LIKE ?", "%#{params[:invoice_number]}%")
                          .distinct
    end

    # opcional: ordenar por ID decrescente
    @invoices = @invoices.order(id: :desc)
    @filtered_count = @invoices.count
    @filtered_total = @invoices.sum(:total)
    @filtered_suppliers = @invoices.select(:supplier_id).distinct.count

    # pega per_page do params, default 10
    per_page = (params[:per_page] || 10).to_i

    pagination = helpers.paginate_records(@invoices, params, per_page: per_page)

    @invoices     = pagination[:records]
    @current_page = pagination[:current_page]
    @total_pages  = pagination[:total_pages]
  end


  # GET /invoices/1 or /invoices/1.json
  def show
    supplier_scope = @invoice.supplier.invoices
                                  .where.not(id: @invoice.id)
                                  .includes(:budget_category)
                                  .order(date_issued: :desc, id: :desc)

    @supplier_invoice_count = supplier_scope.count
    @supplier_invoice_total = supplier_scope.sum(:total)
    @supplier_invoices = supplier_scope.limit(8)

    respond_to do |format|
      format.html
      format.json
      format.pdf do
        pdf = InvoicePdf.new(@invoice)
        send_data pdf.render,
                  filename: "lancamento_#{@invoice.code.presence || @invoice.id}.pdf",
                  type: "application/pdf",
                  disposition: params[:download].present? ? "attachment" : "inline"
      end
    end
  end

  def scan_upload
    raise InvoiceTextractService::Error, "Selecione um PDF ou imagem." unless params[:document].present?
    result = InvoiceTextractService.new(params[:document]).call
    render json: result
  rescue InvoiceTextractService::Error, Aws::Textract::Errors::ServiceError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Seahorse::Client::NetworkingError
    render json: { error: "Não foi possível conectar ao Amazon Textract. Verifique a conexão de rede/DNS do servidor." }, status: :service_unavailable
  end

  # GET /invoices/new
  def new
    @cost_centers = CostCenter.all
    @invoice = Invoice.new
    @invoice.invoice_numbers.build   # 🔑 garante que aparece o campo no form
    @available_purchasers = User.all.order(:name)
  end

  # GET /invoices/1/edit
  def edit
    @cost_centers = CostCenter.all
    @invoice = Invoice.find(params[:id])
    @invoice.invoice_numbers.build if @invoice.invoice_numbers.empty?
    @available_purchasers = User.all.order(:name)
  end

  def dashboard
    # ------------------------------------------------------------
    # 1. Parâmetros de filtro
    # ------------------------------------------------------------
    @month = params[:month].presence&.to_i
    @year  = params[:year].presence&.to_i
    @cost_center_id = params[:cost_center_id].presence

  # ------------------------------------------------------------
  # 2. Escopo base: todas as invoices, com filtro opcional de centro de custo
  #    (usando subconsulta para evitar multiplicação de linhas)
  # ------------------------------------------------------------
    prepare_invoice_sector_filter
    base_scope = apply_invoice_sector_filter(Invoice.all)
  if @cost_center_id.present?
    base_scope = base_scope.where(
      id: InvoiceNumber.where(cost_center_id: @cost_center_id).select(:invoice_id)
    )
  end

    # ------------------------------------------------------------
    # 3. Escopo do período selecionado (mês/ano ou apenas ano)
    #    - Usado para gráficos e cards que dependem do filtro de data.
    # ------------------------------------------------------------
    period_scope = base_scope
    if @month && @year
      period_scope = period_scope.where(
        "EXTRACT(MONTH FROM date_issued) = ? AND EXTRACT(YEAR FROM date_issued) = ?",
        @month, @year
      )
    elsif @year
      period_scope = period_scope.where("EXTRACT(YEAR FROM date_issued) = ?", @year)
    end

    # ------------------------------------------------------------
    # 4. Escopos para janelas fixas: ano atual e mês (condicional)
    #    - Ano atual: sempre de 01/01 até hoje.
    #    - Mês: se houver filtro, usa o mês filtrado; senão, o mês atual.
    #    - Ambos respeitam o filtro de centro de custo.
    # ------------------------------------------------------------
    year_scope = base_scope.where(date_issued: Date.current.beginning_of_year..Date.current)

    if @month && @year
      month_start = Date.new(@year, @month, 1)
      month_end   = month_start.end_of_month
    else
      month_start = Date.current.beginning_of_month
      month_end   = Date.current.end_of_month
    end
    month_scope = base_scope.where(date_issued: month_start..month_end)

    # ------------------------------------------------------------
    # 5. Cards de resumo
    # ------------------------------------------------------------
    @total_spent        = year_scope.sum(:total)
    @invoices_count     = year_scope.count
    @suppliers_count    = period_scope.select(:supplier_id).distinct.count
    @current_month_total = month_scope.sum(:total)
    @current_month_count = month_scope.count

    # ------------------------------------------------------------
    # 6. Período para exibição e filtros de data (usado nos gráficos)
    # ------------------------------------------------------------
    if @month && @year
      start_date = Date.new(@year, @month, 1)
      end_date   = start_date.end_of_month
      @period_display = "#{I18n.t('date.month_names')[@month]} de #{@year}"
      @has_period_filter = true
    else
      start_date = nil
      end_date   = nil
      @period_display = "Mês de Ano"
      @has_period_filter = false
    end

    load_invoice_goals(month_start, month_end, base_scope)

    # ------------------------------------------------------------
    # 7. Gastos por categoria no período selecionado
    # ------------------------------------------------------------
    @current_month_categories = period_scope
      .where(date_issued: start_date..end_date)
      .joins(:budget_category)
      .group('budget_categories.id', 'budget_categories.name', 'budget_categories.sector')
      .select(
        'budget_categories.id',
        'budget_categories.name',
        'budget_categories.sector',
        'SUM(invoices.total) as total',
        'COUNT(invoices.id) as count'
      )
      .map do |record|
        {
          category: BudgetCategory.new(
            id: record.id,
            name: record.name,
            sector: record.sector
          ),
          total: record.total.to_f,
          count: record.count
        }
      end
      .sort_by { |cat| -cat[:total] }

    @period_total = period_scope.where(date_issued: start_date..end_date).sum(:total)

    # ------------------------------------------------------------
    # 8. Média dos últimos 6 meses (usando base_scope, sem filtro de período)
    # ------------------------------------------------------------
    monthly_totals_hash = base_scope
      .group("DATE_TRUNC('month', date_issued)")
      .sum(:total)

    last_six = monthly_totals_hash.values.last(6)
    @monthly_average = last_six.sum / [last_six.size, 1].max

    # ------------------------------------------------------------
    # 9. Gráficos do período selecionado
    # ------------------------------------------------------------
    @spent_per_category = period_scope
      .where(date_issued: start_date..end_date)
      .joins(:budget_category)
      .group('budget_categories.name')
      .sum(:total)
      .transform_values { |value| value.to_f.round(2) }

    @count_per_cost_center = period_scope
      .where(date_issued: start_date..end_date)
      .joins(:budget_category)
      .where(budget_categories: { name: "Manutenção de Caminhão" })
      .joins(invoice_numbers: :cost_center)
      .group('cost_centers.name')
      .count(:total)

    @total_per_cost_center = period_scope
      .where(date_issued: start_date..end_date)
      .joins(:budget_category)
      .where(budget_categories: { name: "Manutenção de Caminhão" })
      .joins(invoice_numbers: :cost_center)
      .group('cost_centers.name')
      .distinct
      .sum('invoices.total')   # soma o total de cada invoice (uma vez)

    @monthly_totals = period_scope
      .group("DATE_TRUNC('month', date_issued)")
      .sum(:total)

    # ------------------------------------------------------------
    # 10. Top fornecedores (período selecionado, exclui Abastecimento)
    # ------------------------------------------------------------
    @top_suppliers = Supplier
      .joins(invoices: :budget_category)
      .merge(period_scope)
      .where.not(budget_categories: { name: "Abastecimento" })
      .select('suppliers.*, COUNT(invoices.id) as invoices_count, SUM(invoices.total) as total_amount')
      .group('suppliers.id')
      .order('total_amount DESC')
      .limit(5)

    # ------------------------------------------------------------
    # 11. Alertas (baseados no escopo base, sem filtro de período)
    # ------------------------------------------------------------
    @recent_invoices      = base_scope.where('date_issued >= ?', 7.days.ago)
    @high_value_invoices  = base_scope.where('total > ?', 10_000)
    @total_invoices_count = base_scope.count
    @latest_invoices      = base_scope
      .includes(:supplier, :budget_category, invoice_numbers: :cost_center)
      .order(date_issued: :desc)
      .limit(10)

    # ------------------------------------------------------------
    # 12. Variação mensal (baseada no escopo base, sem filtro de período)
    # ------------------------------------------------------------
    current_month = base_scope.where('date_issued >= ?', Date.current.beginning_of_month).sum(:total)
    last_month    = base_scope.where(
      'date_issued >= ? AND date_issued < ?',
      1.month.ago.beginning_of_month,
      Date.current.beginning_of_month
    ).sum(:total)

    @monthly_variation = if last_month > 0
      ((current_month - last_month) / last_month * 100).round(2)
    else
      0
    end

    # ------------------------------------------------------------
    # 13. Gráfico de evolução mensal por categoria (ano corrente)
    #     - Agora respeita o filtro de centro de custo.
    # ------------------------------------------------------------
    chart_year = Date.current.year
    category_filter = params[:category_id].presence

    chart_scope = base_scope
      .joins(:budget_category)
      .where(date_issued: Date.new(chart_year, 1, 1)..Date.new(chart_year, 12, 31))

    chart_scope = chart_scope.where(budget_categories: { id: category_filter }) if category_filter

    raw_data = chart_scope.group(
      "budget_categories.id",
      "budget_categories.name",
      "EXTRACT(MONTH FROM date_issued)"
    ).sum(:total)

    months = %w[Jan Fev Mar Abr Mai Jun Jul Ago Set Out Nov Dez]
    grouped = {}

    raw_data.each do |(category_id, category_name, month), total|
      grouped[category_name] ||= Array.new(12, 0)
      grouped[category_name][month.to_i - 1] = total.to_f
    end

    @category_line_chart = grouped.map do |category_name, values|
      {
        name: category_name.titleize,
        data: months.zip(values).to_h
      }
    end

    @all_categories = invoice_budget_categories.order(:name)

    # ------------------------------------------------------------
    # 14. Resposta
    # ------------------------------------------------------------
    respond_to do |format|
      format.html
      format.js
      format.turbo_stream do
        render partial: "category_line_chart", locals: { category_line_chart: @category_line_chart }
      end
      format.html { render partial: "category_line_chart", locals: { category_line_chart: @category_line_chart } } if request.headers["Accept"] == "text/html"
    end
  end


  # POST /invoices or /invoices.json
  def create
    @invoice = Invoice.new(invoice_params.except(:documents))

    respond_to do |format|
      if @invoice.save

        files = params[:invoice][:documents].reject(&:blank?)
        types = params[:document_types] || []

        files.each_with_index do |file, index|
          attachment = @invoice.documents.attach(file).last

          type = types[index].presence || "outro"

          attachment.blob.update!(
            metadata: attachment.blob.metadata.merge(document_type: type)
          )
        end

        format.html { redirect_to @invoice, notice: "Invoice criada com sucesso." }
      else
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /invoices/1
  def update
    respond_to do |format|
      if @invoice.update(invoice_params)
        format.html { redirect_to @invoice, notice: "Invoice was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @invoice }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @invoice.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /invoices/1 or /invoices/1.json
  def destroy
    @invoice.destroy!

    respond_to do |format|
      format.html { redirect_to invoices_path, notice: "Invoice was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def download_document
    doc = @invoice.documents.find(params[:document_id])

    redirect_to rails_blob_url(doc, disposition: "attachment")
  end

  private

  def set_purchasers
    category_id = params.dig(:invoice, :budget_category_id).presence || @invoice&.budget_category_id
    category = BudgetCategory.find_by(id: category_id)

    @purchasers = if category&.user_sector
      User.where(sector: User.sectors.fetch(category.user_sector.to_s)).order(:name)
    else
      User.all.order(:name)
    end
  end

  def prepare_invoice_sector_filter
    @can_filter_invoice_sector = can_view_all_invoice_sectors?
    @invoice_sector_options = BudgetCategory.sectors.values.uniq
    @invoice_sector_filter = if @can_filter_invoice_sector
      sector = params[:sector].presence
      BudgetCategory.sectors.key(sector) || (BudgetCategory.sectors.key?(sector) ? sector : nil)
    end
  end

  def can_view_all_invoice_sectors?
    current_user.admin? || current_user.sector_finance?
  end

  def apply_invoice_sector_filter(scope)
    sectors = if @can_filter_invoice_sector
      @invoice_sector_filter.present? ? [@invoice_sector_filter] : nil
    else
      current_user.budget_sectors
    end

    return scope if sectors.nil?

    scope.joins(:budget_category).where(budget_categories: { sector: sectors })
  end

  def invoice_budget_categories
    categories = BudgetCategory.all
    if @can_filter_invoice_sector
      return categories.where(sector: @invoice_sector_filter) if @invoice_sector_filter.present?

      return categories
    end

    categories.where(sector: current_user.budget_sectors)
  end

  def load_invoice_goals(month_start, month_end, base_scope)
    @invoice_goals = [] unless @has_period_filter
    return unless @has_period_filter

    sectors = if @can_filter_invoice_sector && @invoice_sector_filter.present?
      [@invoice_sector_filter]
    elsif @can_filter_invoice_sector
      BudgetCategory.sectors.values
    else
      current_user.budget_sectors
    end

    @invoice_goals = InvoiceGoal.includes(:budget_categories)
                                 .where(reference_month: month_start, sector: sectors)
                                 .order(:sector, :name)
                                 .map do |goal|
      actual_amount = base_scope
        .where(date_issued: month_start..month_end, budget_category_id: goal.budget_category_ids)
        .sum(:total)
        .to_d

      {
        goal: goal,
        actual_amount: actual_amount,
        percentage: goal.target_amount.to_d.positive? ? (actual_amount / goal.target_amount.to_d * 100).round(1) : 0,
        remaining_amount: [goal.target_amount.to_d - actual_amount, 0.to_d].max
      }
    end
  end


  # Use callbacks to share common setup or constraints between actions.
  def set_invoice
    @invoice = Invoice.find(params[:id])
    return if can_view_all_invoice_sectors?

    category_sector = @invoice.budget_category&.sector
    return if current_user.budget_sectors.include?(category_sector)

    redirect_to invoices_path, alert: "Você não tem acesso a este setor."
  end

    # Only allow a list of trusted parameters through.
  def invoice_params
    params.require(:invoice).permit(
      :supplier_id, :date_issued, :due_date, :total, :purchaser_id, :budget_category_id, :cost_center_id, :notes, :code, documents: [],
      invoice_numbers_attributes: [:id, :number, :amount, :cost_center_id, :_destroy]
    )
  end
end
