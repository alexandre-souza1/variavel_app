class RoutineTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine_template, only: %i[
    show
    edit
    update
    destroy
  ]
  before_action :authorize_management, only: %i[edit update destroy]

  def index
    @routine_templates = RoutineTemplate.visible_to(current_user).independent.order(:name)
  end

  def show
    @routine_template = RoutineTemplate.visible_to(current_user).includes(routine_categories: :routine_indicators).find(params[:id])
    @action_plan = @routine_template.action_plan
    @can_manage_template = @routine_template.manageable_by?(current_user)
  end

  def new
    @routine_template = RoutineTemplate.new
  end

  def create
    @routine_template = RoutineTemplate.new(routine_template_params)

    if @routine_template.save
      redirect_to @routine_template,
                  notice: "Template criado com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @routine_template.update(routine_template_params)
      redirect_to @routine_template,
                  notice: "Template atualizado com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @routine_template.action_plan
      redirect_to action_plan_gerot_template_path(@routine_template.action_plan), alert: "O modelo pertence ao plano de ação."
    elsif @routine_template.destroy
      redirect_to routine_templates_path, notice: "Modelo removido."
    else
      redirect_to @routine_template, alert: @routine_template.errors.full_messages.to_sentence
    end
  end

  private

  def set_routine_template
    @routine_template = RoutineTemplate.visible_to(current_user).find(params[:id])
    @action_plan = @routine_template.action_plan
  end

  def authorize_management
    head :forbidden unless @routine_template.manageable_by?(current_user)
  end

  def routine_template_params
    attributes = params.require(:routine_template).permit(
      :name,
      :description,
      :active,
      :sector
    )
    attributes.except!(:sector) if @routine_template&.action_plan
    attributes
  end
end
