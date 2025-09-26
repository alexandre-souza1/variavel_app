# app/controllers/admin/budget_categories_controller.rb
class Admin::BudgetCategoriesController < ApplicationController
  before_action :set_budget_category, only: [:edit, :update, :destroy]

  def index
    @budget_categories = BudgetCategory.all.order(:sector, :name)
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

  def edit
  end

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

  private

  def set_budget_category
    @budget_category = BudgetCategory.find(params[:id])
  end

  def budget_category_params
    params.require(:budget_category).permit(:name, :sector)
  end
end
