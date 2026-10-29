class Admin::InvoiceGoalsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin_or_finance!
  before_action :set_invoice_goal, only: [:edit, :update, :destroy]

  def index
    source = InvoiceGoal.find(params[:editor]) if params[:editor].present? && params[:editor] != "new"
    load_index(editor_source: source, active_editor: params[:editor])
  end

  def new
    source = InvoiceGoal.find(params[:version_of]) if params[:version_of].present?
    redirect_to admin_invoice_goals_path(editor: source&.id || "new")
  end

  def create
    @invoice_goal = InvoiceGoal.new(invoice_goal_params)

    if InvoiceGoal.exists?(name: @invoice_goal.name, sector: @invoice_goal.sector)
      @invoice_goal.errors.add(:name, "já existe neste setor. Use Alterar meta no indicador existente.")
      render_editor_errors
    elsif @invoice_goal.save
      redirect_to admin_invoice_goals_path, notice: "Meta criada com sucesso.", status: :see_other
    else
      render_editor_errors
    end
  end

  def edit
    redirect_to admin_invoice_goals_path(editor: @invoice_goal.id)
  end

  def update
    @source = @invoice_goal
    @invoice_goal = @source.change_from(change_params)
    if @invoice_goal.persisted? && @invoice_goal.errors.empty?
      redirect_to admin_invoice_goals_path, notice: "Meta atualizada com sucesso.", status: :see_other
    else
      render_editor_errors
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

  def load_index(editor_source: nil, editor_goal: nil, active_editor: nil)
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

    @budget_categories = BudgetCategory.order(:sector, :name).to_a
    @new_invoice_goal = if editor_source.nil? && editor_goal
      editor_goal
    else
      InvoiceGoal.new(reference_month: @month)
    end
    sources = @indicators.flat_map { |indicator| [indicator[:source], *indicator[:scheduled]] }
    sources << editor_source if editor_source
    @editors = sources.uniq(&:id).map do |source|
      goal = if editor_source&.id == source.id && editor_goal
        editor_goal
      else
        draft = source.dup
        draft.budget_categories = source.budget_categories
        draft.reference_month = [@month, source.reference_month].max
        draft.ends_at = nil
        draft
      end
      history = @indicators.find { |indicator| indicator[:sector] == source.sector && indicator[:name] == source.name }[:history]
      scheduled_change = history.select { |record| record.reference_month > (goal.reference_month || @month) }.min_by(&:reference_month)
      { source: source, invoice_goal: goal, scheduled_change: scheduled_change,
        budget_categories: @budget_categories.select { |category| category.sector == source.sector } }
    end
    @active_editor = active_editor.to_s
  end

  def render_editor_errors
    load_index(editor_source: @source, editor_goal: @invoice_goal, active_editor: @source&.id || "new")
    render :index, status: :unprocessable_entity
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
