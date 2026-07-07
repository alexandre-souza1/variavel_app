class InvoicesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_invoice, only: %i[ show edit update destroy ]
  before_action :set_purchasers, only: [:new, :edit, :create, :update]

  # GET /invoices or /invoices.json
  def index
    @invoices = Invoice.includes(:supplier, :invoice_numbers).all

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

    # pega per_page do params, default 10
    per_page = (params[:per_page] || 10).to_i

    pagination = helpers.paginate_records(@invoices, params, per_page: per_page)

    @invoices     = pagination[:records]
    @current_page = pagination[:current_page]
    @total_pages  = pagination[:total_pages]
  end


  # GET /invoices/1 or /invoices/1.json
  def show
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
  base_scope = Invoice.all
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

    chart_scope = Invoice.joins(:budget_category)
                        .where(date_issued: Date.new(chart_year, 1, 1)..Date.new(chart_year, 12, 31))

    if @cost_center_id.present?
      chart_scope = chart_scope.joins(:invoice_numbers)
                              .where(invoice_numbers: { cost_center_id: @cost_center_id })
                              .distinct
    end

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

    @all_categories = BudgetCategory.all.order(:name)

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
    invoice = Invoice.find(params[:id])
    doc = invoice.documents.find(params[:document_id])

    redirect_to rails_blob_url(doc, disposition: "attachment")
  end

  private

  def set_purchasers
    @purchasers = User.all.order(:name)  # ✅ Mude para .all por enquanto
  end


  # Use callbacks to share common setup or constraints between actions.
  def set_invoice
    @invoice = Invoice.find(params[:id])
  end

    # Only allow a list of trusted parameters through.
  def invoice_params
    params.require(:invoice).permit(
      :supplier_id, :date_issued, :due_date, :total, :purchaser_id, :budget_category_id, :cost_center_id, :notes, :code, documents: [],
      invoice_numbers_attributes: [:id, :number, :cost_center_id, :_destroy]
    )
  end
end
