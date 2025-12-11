class InvoicesController < ApplicationController
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

    # 🔹 pega filtros (se existirem)
    @month = params[:month].presence&.to_i
    @year  = params[:year].presence&.to_i

    invoices_scope = Invoice.joins(:invoice_numbers).distinct

    invoice_ids = invoices_scope.pluck(:id).uniq

    # aplica filtro por cost center se houver
    if params[:cost_center_id].present?
      invoices_scope = invoices_scope.where(invoice_numbers: { cost_center_id: params[:cost_center_id] })
    end

    # 🔹 aplica filtros de período
    if @month && @year
      invoices_scope = invoices_scope.where(
        "EXTRACT(MONTH FROM date_issued) = ? AND EXTRACT(YEAR FROM date_issued) = ?",
        @month, @year
      )
    elsif @year
      invoices_scope = invoices_scope.where("EXTRACT(YEAR FROM date_issued) = ?", @year)
    end

    # 🔹 Cards de resumo
    @total_spent = Invoice.where(id: invoice_ids).sum(:total)
    @invoices_count = invoice_ids.count
    @suppliers_count = Invoice.where(id: invoice_ids).select(:supplier_id).distinct.count
    @current_month_total = Invoice.where(id: invoice_ids)
      .where("date_issued >= ?", Date.today.beginning_of_month)
      .sum(:total)

    @current_month_count = Invoice.where(id: invoice_ids)
      .where("date_issued >= ?", Date.today.beginning_of_month)
      .count

    # 🔹 Gastos por categoria do período filtrado (CORRIGIDO)
    if @month && @year
      # Se tem filtro de mês/ano específico, usa esse período
      start_date = Date.new(@year, @month, 1)
      end_date = start_date.end_of_month
      @period_display = "#{I18n.t('date.month_names')[@month]}/#{@year}"
      @has_period_filter = true
    else
      # Se não tem filtro, mostra mensagem para selecionar
      start_date = nil
      end_date = nil
      @period_display = "Mês/Ano"
      @has_period_filter = false
    end

  @current_month_categories = Invoice.where(id: invoice_ids)
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

    # Também precisamos atualizar o total do período para calcular as porcentagens
    @period_total = invoices_scope.where(date_issued: start_date..end_date).sum(:total)

    # média dos últimos 6 meses no escopo filtrado
    monthly_totals_hash = Invoice.where(id: invoice_ids)
      .group("DATE_TRUNC('month', date_issued)")
      .sum(:total)
    @monthly_average = monthly_totals_hash.values.last(6).sum / [monthly_totals_hash.values.last(6).size, 1].max

    # 🔹 Gráficos
    @spent_per_category = Invoice.where(id: invoice_ids)
              .where(date_issued: start_date..end_date)
              .joins(:budget_category)
              .group('budget_categories.name')
              .sum(:total)
              .transform_values { |value| value.to_f.round(2) }


    @count_per_cost_center = Invoice.where(id: invoice_ids)
                                      .where(date_issued: start_date..end_date)
                                      .joins(:budget_category)
                                      .where(budget_categories: { name: "Manutenção de Caminhão" })
                                      .joins(invoice_numbers: :cost_center)
                                      .group('cost_centers.name')
                                      .count(:total)

    @monthly_totals = invoices_scope.group("DATE_TRUNC('month', date_issued)").sum(:total)

    # 🔹 Top fornecedores (mantém filtro e exclui abastecimento)
    @top_suppliers = Supplier.joins(invoices: :budget_category)
                            .merge(invoices_scope)
                            .where.not(budget_categories: { name: "Abastecimento" })
                            .select('suppliers.*, COUNT(invoices.id) as invoices_count, SUM(invoices.total) as total_amount')
                            .group('suppliers.id')
                            .order('total_amount DESC')
                            .limit(5)

    # 🔹 Alertas
    @recent_invoices = invoices_scope.where('date_issued >= ?', 7.days.ago)
    @high_value_invoices = invoices_scope.where('total > ?', 10_000)
    @total_invoices_count = invoices_scope.count
    @latest_invoices = invoices_scope
      .includes(:supplier, :budget_category, invoice_numbers: :cost_center)
      .order(date_issued: :desc)
      .limit(10)

    # 🔹 Variação mensal (baseada no escopo filtrado)
    current_month = invoices_scope.where('date_issued >= ?', Date.today.beginning_of_month).sum(:total)
    last_month = invoices_scope.where('date_issued >= ? AND date_issued < ?',
                                      1.month.ago.beginning_of_month, Date.today.beginning_of_month).sum(:total)
    @monthly_variation = last_month > 0 ? ((current_month - last_month) / last_month * 100).round(2) : 0
  end


  # POST /invoices or /invoices.json
  def create
    @invoice = Invoice.new(invoice_params)

    respond_to do |format|
      if @invoice.save
        format.html { redirect_to @invoice, notice: "Invoice was successfully created." }
        format.json { render :show, status: :created, location: @invoice }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @invoice.errors, status: :unprocessable_entity }
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
    document_index = params[:document_index].to_i

    if invoice.document_urls.present? && invoice.document_urls[document_index]
      sharepoint_url = invoice.document_urls[document_index]

      # Tenta obter a URL de download direta
      service = OnedriveService.new
      download_url = service.get_direct_download_url(sharepoint_url) ||
                    service.create_anonymous_download_link(sharepoint_url)

      if download_url
        # Verifica se a URL de download é válida (não é a URL original do SharePoint)
        if download_url != sharepoint_url
          # URL de download direta obtida com sucesso - redireciona
          redirect_to download_url, allow_other_host: true
        else
          # Não conseguiu obter URL de download direta - arquivo pode não existir
          redirect_to invoices_path, alert: 'Arquivo não encontrado no OneDrive. O arquivo pode ter sido excluído.'
        end
      else
        # Não conseguiu obter nenhuma URL de download
        redirect_to invoices_path, alert: 'Arquivo não encontrado no OneDrive. O arquivo pode ter sido excluído.'
      end
    else
      redirect_to invoices_path, alert: 'Documento não encontrado.'
    end
  rescue => e
    Rails.logger.error("Erro ao baixar documento: #{e.message}")
    redirect_to invoices_path, alert: 'Erro ao tentar baixar o arquivo. O arquivo pode ter sido excluído.'
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
