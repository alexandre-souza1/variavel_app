class RoutineGeneratorsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_generation_context, only: %i[new create]
  before_action :set_routine, only: %i[edit update]

  def new
  end

  def create
    if @template.blank? || !@template.active? || (@action_plan && @template.default_selected_indicator_ids.blank?)
      @error_message = "Cadastre os indicadores no modelo do plano antes de gerar um GEROT."
      render :new, status: :unprocessable_entity
      return
    end

    routine = Routines::Generator.call(
      template: @template,
      action_plan: @action_plan,
      period_start: Date.iso8601(params[:period_start].to_s),
      period_end: Date.iso8601(params[:period_end].to_s),
      created_by: current_user,
      indicator_ids: Array(params[:indicator_ids]).reject(&:blank?),
      bucket_ids: category_bucket_params,
      task_generation_mode: params[:task_generation_mode].presence || :commented_deviation
    )

    redirect_to routine, notice: @action_plan ? "GEROT criado no plano #{@action_plan.name}." : "GEROT independente criado."
  rescue ActiveRecord::RecordInvalid => error
    @error_message = error.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    @error_message = "Este modelo já possui um GEROT neste período e plano."
    render :new, status: :unprocessable_entity
  rescue ArgumentError => error
    @error_message = error.message == "invalid date" ? "Informe um período válido." : error.message
    render :new, status: :unprocessable_entity
  end

  def edit
    ensure_editable_routine
  end

  def update
    return unless ensure_editable_routine

    ActiveRecord::Base.transaction do
      @routine.update!(routine_settings_params)
      Routines::IndicatorUpdater.call(routine: @routine, indicator_ids: Array(params[:indicator_ids]).reject(&:blank?))
      if @action_plan
        Routines::CategoryBucketMapper.call(
          action_plan: @action_plan,
          categories: @routine.selected_indicators.map(&:routine_category).uniq,
          bucket_ids: category_bucket_params
        )
      end
    end

    redirect_to @routine, notice: "Configurações do GEROT atualizadas."
  rescue ActiveRecord::RecordInvalid => error
    @error_message = error.record.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
  rescue ArgumentError => error
    @error_message = error.message
    render :edit, status: :unprocessable_entity
  end

  private

  def set_generation_context
    if params[:action_plan_id].present?
      @action_plan = ActionPlan.visible_to(current_user).find(params[:action_plan_id])
      return head :forbidden unless @action_plan.manageable_by?(current_user)
      @template = @action_plan.gerot_template
      return redirect_to new_action_plan_gerot_template_path(@action_plan) unless @template
      if params[:routine_template_id].present? && params[:routine_template_id].to_i != @template.id
        raise ActiveRecord::RecordNotFound
      end
      load_category_buckets
    else
      @template = RoutineTemplate.visible_to(current_user).independent.active.find(params[:routine_template_id])
    end

    year = params[:year].to_i
    year = @action_plan&.gerot_year || Date.current.year unless year.between?(1900, 9998)
    month = params[:month].to_i
    month = Date.current.month unless month.between?(1, 12)
    @period_start = params[:period_start].presence || Date.new(year, month, 1)
    @period_end = params[:period_end].presence || Date.new(year, month, 1).end_of_month
  end

  def set_routine
    @routine = Routine.visible_to(current_user).includes(:routine_template, :action_plan).find(params[:routine_id])
    @action_plan = @routine.action_plan
    load_category_buckets if @action_plan
  end

  def load_category_buckets
    Routines::PlanTemplateSynchronizer.call(action_plan: @action_plan)
    @category_buckets = @action_plan.routine_category_buckets.index_by(&:routine_category_id)
    @destination_buckets = @action_plan.buckets.to_a
  end

  def ensure_editable_routine
    unless @routine.manageable_by?(current_user)
      head :forbidden
      return false
    end
    return true unless @routine.closed? || @routine.archived?

    redirect_to @routine, alert: "Este GEROT não permite mais editar os indicadores."
    false
  end

  def category_bucket_params
    source = @template || @routine.routine_template
    category_ids = source.routine_categories.pluck(:id).map(&:to_s)
    params.fetch(:category_bucket_ids, ActionController::Parameters.new).permit(*category_ids).to_h
  end

  def routine_settings_params
    settings = {
      weekly_reference_weekday: params[:weekly_reference_weekday].presence&.to_i,
      monthly_reference_day: params[:monthly_reference_day].presence&.to_i
    }
    settings[:task_generation_mode] = params[:task_generation_mode] if params[:task_generation_mode].present?
    settings
  end
end
