class ActionPlanRoutinesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_plan

  def new
    load_adaptation
  end

  def create
    load_adaptation
    unless @routine
      @error_message = "Escolha um GEROT independente para adaptar."
      return render :new, status: :unprocessable_entity
    end
    unless params.key?(:category_bucket_ids) || (@categories.empty? && params[:adaptation_reviewed] == "1")
      return redirect_to new_action_plan_gerot_path(@action_plan, routine_id: @routine.id)
    end
    Routines::PlanLinker.call(routine: @routine, action_plan: @action_plan, bucket_ids: adaptation_params)

    redirect_to action_plan_path(@action_plan, view: "gerots", year: @routine.period_start.year),
                notice: "GEROT adaptado ao modelo do plano. Os preenchimentos e o histórico foram preservados."
  rescue ActiveRecord::RecordInvalid => error
    @error_message = error.record.errors.full_messages.to_sentence
    @routine.reload
    render :new, status: :unprocessable_entity
  end

  private

  def set_plan
    @action_plan = ActionPlan.visible_to(current_user).find(params[:action_plan_id])
    head :forbidden unless @action_plan.manageable_by?(current_user)
  end

  def load_adaptation
    @unlinked_gerots = Routine.visible_to(current_user).where(action_plan_id: nil)
      .joins(:routine_template).where(routine_templates: { sector: @action_plan.sector }).order(period_start: :desc)
    @unlinked_gerots = @unlinked_gerots.where(created_by: current_user) unless current_user.admin?
    @routine = @unlinked_gerots.find(params[:routine_id]) if params[:routine_id].present?
    @categories = @routine ? @routine.routine_template.routine_categories.includes(:routine_indicators) : []
    @destination_buckets = @action_plan.buckets.to_a
  end

  def adaptation_params
    params.fetch(:category_bucket_ids, ActionController::Parameters.new).permit(*@categories.map { |category| category.id.to_s }).to_h
  end
end
