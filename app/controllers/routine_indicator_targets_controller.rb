class RoutineIndicatorTargetsController < ApplicationController
  before_action :authenticate_user!

  before_action :set_template
  before_action :set_category
  before_action :set_indicator
  before_action :set_target, only: %i[
    edit
    update
    destroy
  ]

  def index
    @routine_indicator_targets =
      @indicator.routine_indicator_targets
               .order(starts_at: :desc)
  end

  def new
    @routine_indicator_target =
      @indicator.routine_indicator_targets.new
  end

  def create
    @routine_indicator_target =
      @indicator.routine_indicator_targets.new(
        normalized_target_params
      )

    if @routine_indicator_target.save
      redirect_to targets_path,
                  notice: "Meta criada com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @routine_indicator_target.update(normalized_target_params)
      redirect_to targets_path,
                  notice: "Meta atualizada com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @routine_indicator_target.destroy

    redirect_to targets_path,
                notice: "Meta removida com sucesso."
  end

  private

  def set_template
    @template = RoutineTemplate.find(params[:routine_template_id])
  end

  def set_category
    @category =
      @template.routine_categories.find(
        params[:routine_category_id]
      )
  end

  def set_indicator
    @indicator =
      @category.routine_indicators.find(
        params[:routine_indicator_id]
      )
  end

  def set_target
    @routine_indicator_target =
      @indicator.routine_indicator_targets.find(
        params[:id]
      )
  end

  def target_params
    params.require(:routine_indicator_target).permit(
      :goal,
      :starts_at,
      :ends_at
    )
  end

  def normalized_target_params
    permitted_params = target_params
    goal = permitted_params[:goal]&.strip

    permitted_params[:goal] =
      if goal.blank?
        nil
      elsif numeric_indicator?
        goal.tr(",", ".")
      elsif duration_indicator?
        goal.tr(".", ":")
      else
        goal
      end

    permitted_params
  end

  def numeric_indicator?
    @indicator.value_type.in?(
      %w[integer decimal percentage currency]
    )
  end

  def duration_indicator?
    @indicator.duration?
  end

  def targets_path
    routine_template_routine_category_routine_indicator_routine_indicator_targets_path(
      @template,
      @category,
      @indicator
    )
  end
end
