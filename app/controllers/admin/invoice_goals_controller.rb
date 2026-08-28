class Admin::InvoiceGoalsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin_or_finance!
  before_action :set_invoice_goal, only: [:edit, :update, :destroy]
  before_action :load_budget_categories, only: [:new, :edit, :create, :update]

  def index
    @invoice_goals = InvoiceGoal.includes(:budget_categories)
                                .order(reference_month: :desc, sector: :asc, name: :asc)
  end

  def new
    @invoice_goal = InvoiceGoal.new(reference_month: Date.current.beginning_of_month)
  end

  def create
    @invoice_goal = InvoiceGoal.new(invoice_goal_params)

    if @invoice_goal.save
      redirect_to admin_invoice_goals_path, notice: "Meta criada com sucesso."
    else
      load_budget_categories
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @invoice_goal.update(invoice_goal_params)
      redirect_to admin_invoice_goals_path, notice: "Meta atualizada com sucesso."
    else
      load_budget_categories
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @invoice_goal.destroy
    redirect_to admin_invoice_goals_path, notice: "Meta excluída com sucesso."
  end

  private

  def set_invoice_goal
    @invoice_goal = InvoiceGoal.find(params[:id])
  end

  def load_budget_categories
    sector = @invoice_goal&.sector || params.dig(:invoice_goal, :sector)
    sector_key = BudgetCategory.sectors.key(sector.to_s) || sector.to_s

    @budget_categories = if sector_key.present?
      BudgetCategory.where(sector: sector_key).order(:name)
    else
      BudgetCategory.order(:sector, :name)
    end
  end

  def invoice_goal_params
    params.require(:invoice_goal).permit(
      :name, :sector, :reference_month, :target_amount, budget_category_ids: []
    )
  end
end
