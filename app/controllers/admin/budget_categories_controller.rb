# app/controllers/admin/budget_categories_controller.rb
class Admin::BudgetCategoriesController < ApplicationController
  before_action :set_budget_category, only: [:edit, :update, :destroy, :expenses]

  def index
    @budget_categories = BudgetCategory.order(:sector, :name)
  end

  def new
    @budget_category = BudgetCategory.new
  end

  def create
    @budget_category = BudgetCategory.new(budget_category_params)
    if @budget_category.save
      redirect_to admin_budget_categories_path, notice: 'Categoria orçamentária criada com sucesso.'
    else
      render :new
    end
  end

  def edit; end

  def update
    if @budget_category.update(budget_category_params)
      redirect_to admin_budget_categories_path, notice: 'Categoria orçamentária atualizada com sucesso.'
    else
      render :edit
    end
  end

  def destroy
    @budget_category.destroy
    redirect_to admin_budget_categories_path, notice: 'Categoria orçamentária excluída com sucesso.'
  end

  # ✅ Requisição assíncrona (via Stimulus)
  def expenses
    invoices_scope = @budget_category.invoices
                                     .includes(:supplier, invoice_numbers: :cost_center)
                                     .order(date_issued: :desc)

    # 🔹 Aplica filtro de mês/ano (vindo da dashboard)
    if params[:month].present? && params[:year].present?
      month = params[:month].to_i
      year  = params[:year].to_i
      start_date = Date.new(year, month, 1)
      end_date   = start_date.end_of_month

      invoices_scope = invoices_scope.where(date_issued: start_date..end_date)
    elsif params[:year].present?
      year = params[:year].to_i
      invoices_scope = invoices_scope.where("EXTRACT(YEAR FROM date_issued) = ?", year)
    end

    # 🔹 Paginação manual
    per_page = (params[:per_page] || 10).to_i
    pagination = helpers.paginate_records(invoices_scope, params, per_page: per_page)

    @expenses      = pagination[:records]
    @current_page  = pagination[:current_page]
    @total_pages   = pagination[:total_pages]

    render partial: "admin/budget_categories/expenses_table",
           locals: {
             category: @budget_category,
             expenses: @expenses,
             current_page: @current_page,
             total_pages: @total_pages
           }
  end

  private

  def set_budget_category
    @budget_category = BudgetCategory.find(params[:id])
  end

  def budget_category_params
    params.require(:budget_category).permit(:name, :sector)
  end
end
