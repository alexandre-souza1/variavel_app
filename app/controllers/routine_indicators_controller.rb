class RoutineIndicatorsController < ApplicationController
  before_action :authenticate_user!

  before_action :set_template
  before_action :set_category
  before_action :set_indicator, only: %i[
    edit
    update
    destroy
  ]

  def new
    @routine_indicator =
      @category.routine_indicators.new
  end

  def create
    @routine_indicator =
      @category.routine_indicators.new(indicator_params)

    @routine_indicator.position =
      @category.routine_indicators.count

    if @routine_indicator.save
      redirect_to @template,
                  notice: "Indicador criado."
    else
      render :new,
             status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @routine_indicator.update(indicator_params)
      redirect_to @template,
                  notice: "Indicador atualizado."
    else
      render :edit,
             status: :unprocessable_entity
    end
  end

  def destroy
    @routine_indicator.destroy

    redirect_to @template,
                notice: "Indicador removido."
  end

  private

  def set_template
    @template =
      RoutineTemplate.find(params[:routine_template_id])
  end

  def set_category
    @category =
      @template.routine_categories.find(params[:routine_category_id])
  end

  def set_indicator
    @routine_indicator =
      @category.routine_indicators.find(params[:id])
  end

  def indicator_params
    params
      .require(:routine_indicator)
      .permit(
        :name,
        :description,
        :calculation_type,
        :value_type,
        :goal_direction,
        :required,
        :active
      )
  end
end
