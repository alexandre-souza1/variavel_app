class ChecklistTemplatesController < ApplicationController
  before_action :authenticate_user!

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
      render :new
    end
  end

  def show
    @template = ChecklistTemplate.find(params[:id])
    @item = ChecklistItem.new
  end

  private

  def template_params
    params.require(:checklist_template).permit(:name, :plate_required, :setor)
  end
end
