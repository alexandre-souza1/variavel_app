class InvoicesController < ApplicationController
  before_action :set_invoice, only: %i[ show edit update destroy ]

  # GET /invoices or /invoices.json
  def index
    @invoices = Invoice.includes(:supplier, :invoice_numbers).all

    # filtro por ID da invoice
    @invoices = @invoices.where(id: params[:id]) if params[:id].present?

    # filtro por CNPJ do fornecedor
    if params[:supplier_cnpj].present?
      @invoices = @invoices.joins(:supplier)
                          .where("suppliers.cnpj LIKE ?", "%#{params[:supplier_cnpj]}%")
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
  end


  # GET /invoices/1 or /invoices/1.json
  def show
  end

  # GET /invoices/new
  def new
    @invoice = Invoice.new
    @invoice.invoice_numbers.build   # 🔑 garante que aparece o campo no form
  end

  # GET /invoices/1/edit
  def edit
    @invoice = Invoice.find(params[:id])
    @invoice.invoice_numbers.build if @invoice.invoice_numbers.empty?
  end

  def dashboard
    @total_spent = Invoice.sum(:total)

    # garante que as chaves sejam inteiros
    @spent_per_category = Invoice.all.group_by(&:budget_category).transform_values { |invoices| invoices.sum(&:total) }

    @latest_invoices = Invoice.includes(:supplier, :invoice_numbers).order(created_at: :desc).limit(10)
    @invoices_count = Invoice.count
    @suppliers_count = Supplier.count
    @current_month_total = Invoice.where('date_issued >= ?', Date.today.beginning_of_month).sum(:total)
    @current_month_count = Invoice.where('date_issued >= ?', Date.today.beginning_of_month).count
    @monthly_average = Invoice.where('date_issued >= ?', 6.months.ago).average(:total).to_f
    @monthly_totals = Invoice.group_by_month(:date_issued, format: "%b %Y").sum(:total)
    @top_suppliers = Supplier.joins(:invoices)
                            .select('suppliers.*, COUNT(invoices.id) as invoices_count, SUM(invoices.total) as total_amount')
                            .group('suppliers.id')
                            .order('total_amount DESC')
                            .limit(5)
    @recent_invoices = Invoice.where('date_issued >= ?', 7.days.ago)
    @high_value_invoices = Invoice.where('total > ?', 10000)
    @total_invoices_count = Invoice.count

    # Cálculo de variação mensal
    current_month = Invoice.where('date_issued >= ?', Date.today.beginning_of_month).sum(:total)
    last_month = Invoice.where('date_issued >= ? AND date_issued < ?',
                              1.month.ago.beginning_of_month, Date.today.beginning_of_month).sum(:total)
    @monthly_variation = last_month > 0 ? ((current_month - last_month) / last_month * 100).round(2) : 0
  end

  # POST /invoices or /invoices.json
  def create
    @invoice = Invoice.new(invoice_params)

    respond_to do |format|
      if @invoice.save
        # ❌ REMOVER a lógica de upload - já está no model
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
        # ❌ REMOVER a lógica de upload - já está no model
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
    # Use callbacks to share common setup or constraints between actions.
    def set_invoice
      @invoice = Invoice.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
  def invoice_params
    params.require(:invoice).permit(
      :supplier_id, :date_issued, :due_date, :total, :purchaser, :budget_category, :cost_center, :notes, :code, documents: [],
      invoice_numbers_attributes: [:id, :number, :_destroy]
    )
  end
end
