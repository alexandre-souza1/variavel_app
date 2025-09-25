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
