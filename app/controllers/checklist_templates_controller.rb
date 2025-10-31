class ChecklistTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template, only: [:show, :edit, :update]

  def index
    @templates = ChecklistTemplate.all
  end

  def new
    @template = ChecklistTemplate.new
  end

  def create
    @template = ChecklistTemplate.new(template_params)
    if @template.save
      redirect_to checklist_template_path(@template), notice: "Template criado com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @item = ChecklistItem.new
  end

  def edit
    @item = ChecklistItem.new
  end

  def update
    @item = ChecklistItem.new
    if @template.update(template_params)
      redirect_to checklist_template_path(@template), notice: "Template atualizado com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_template
    @template = ChecklistTemplate.find(params[:id])
  end

  def template_params
    params.require(:checklist_template).permit(
      :name,
      :plate_required,
      :kilometer_required,
      :gas_state_required,
      :vehicle_model_required,
      :responsavel_required,
      :setor
    )
  end
end
