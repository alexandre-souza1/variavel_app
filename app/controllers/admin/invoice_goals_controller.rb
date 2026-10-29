class Admin::InvoiceGoalsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin_or_finance!
  before_action :set_invoice_goal, only: [:edit, :update, :destroy]

  def index
    @month = Date.current.beginning_of_month
    current_ids = InvoiceGoal.effective_on(@month).pluck(:id).to_set
    @indicators = InvoiceGoal.includes(:budget_categories)
      .order(:sector, :name, reference_month: :desc)
      .group_by { |goal| [goal.sector, goal.name] }
      .map do |(sector, name), history|
        current = history.find { |goal| current_ids.include?(goal.id) }
        scheduled = history.select { |goal| goal.reference_month > @month }.reverse
        { sector: sector, name: name, current: current, scheduled: scheduled,
          source: current || scheduled.first || history.first, history: history }
      end
  end

  def new
    if params[:version_of].present?
      return redirect_to edit_admin_invoice_goal_path(InvoiceGoal.find(params[:version_of]))
    end
    @invoice_goal = InvoiceGoal.new(reference_month: Date.current.beginning_of_month)
    load_budget_categories
  end

  def create
    @invoice_goal = InvoiceGoal.new(invoice_goal_params)

    if InvoiceGoal.exists?(name: @invoice_goal.name, sector: @invoice_goal.sector)
      @invoice_goal.errors.add(:name, "já existe neste setor. Use Alterar meta no indicador existente.")
      load_budget_categories
      render :new, status: :unprocessable_entity
    elsif @invoice_goal.save
      redirect_to admin_invoice_goals_path, notice: "Meta criada com sucesso."
    else
      load_budget_categories
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @source = @invoice_goal
    @invoice_goal = @source.dup
    @invoice_goal.budget_categories = @source.budget_categories
    @invoice_goal.reference_month = [Date.current.beginning_of_month, @source.reference_month].max
    @invoice_goal.ends_at = nil
    prepare_change_form
  end

  def update
    @source = @invoice_goal
    @invoice_goal = @source.change_from(change_params)
    if @invoice_goal.persisted? && @invoice_goal.errors.empty?
      redirect_to admin_invoice_goals_path, notice: "Meta atualizada com sucesso."
    else
      prepare_change_form
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
    @budget_categories = BudgetCategory.order(:sector, :name)
    @budget_categories = @budget_categories.where(sector: @source.sector) if @source
  end

  def prepare_change_form
    load_budget_categories
    @scheduled_change = InvoiceGoal.where(name: @source.name, sector: @source.sector)
      .where("reference_month > ?", @invoice_goal.reference_month || Date.current.beginning_of_month)
      .order(:reference_month).first
  end

  def invoice_goal_params
    params.require(:invoice_goal).permit(
      :name, :sector, :reference_month, :target_amount, budget_category_ids: []
    )
  end

  def change_params
    params.require(:invoice_goal).permit(:reference_month, :target_amount, budget_category_ids: []).to_h.symbolize_keys
  end
end
