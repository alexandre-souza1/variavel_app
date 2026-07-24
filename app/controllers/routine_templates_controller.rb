class RoutineTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine_template, only: %i[
    show
    edit
    update
    destroy
  ]

  def index
    @routine_templates = RoutineTemplate.order(:name)
  end

  def show
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
    @routine_template.destroy

    redirect_to routine_templates_path,
                notice: "Template removido."
  end

  private

  def set_routine_template
    @routine_template = RoutineTemplate.find(params[:id])
  end

  def routine_template_params
    params.require(:routine_template).permit(
      :name,
      :description,
      :active
    )
  end
end
