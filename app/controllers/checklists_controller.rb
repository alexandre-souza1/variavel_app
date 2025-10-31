class ChecklistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template, only: [:new] # Adicione esta linha

  def index
    @checklists = current_user.checklists.includes(:checklist_template)
  end

  def historic
    @checklists = Checklist.includes(:checklist_template)
  end

  def new
    @template = ChecklistTemplate.find(params[:template_id])
    @checklist = Checklist.new(checklist_template: @template)

    @template.checklist_items.each do |item|
      @checklist.checklist_responses.build(checklist_item: item)
    end

    # Filtra as placas pelo setor do template
    @plates = Plate.where(setor: @template.setor)
  end

  def create
    @checklist = current_user.checklists.new(checklist_params)
    @template = ChecklistTemplate.find(checklist_params[:checklist_template_id])

    if @checklist.save
      redirect_to @checklist, notice: 'Checklist enviado com sucesso.'
    else
      # Recarrega os checklist_items para o form funcionar corretamente
      @checklist.checklist_responses.each do |response|
        response.checklist_item ||= ChecklistItem.find(response.checklist_item_id)
      end

      # Recarrega as placas para o formulário (se der erro)
      @plates = Plate.where(setor: @template.setor)

      render :new
    end
  end

  def show
      @checklist = Checklist.find(params[:id])
        respond_to do |format|
      format.html
      format.pdf do
        pdf = ChecklistPdf.new(@checklist)
        send_data pdf.render,
                  filename: "checklist_#{@checklist.id}.pdf",
                  type: "application/pdf",
                  disposition: "inline"
      end
    end
  end

  private

  def set_template
    @template = ChecklistTemplate.find(params[:template_id])
  end

  def checklist_params
    params.require(:checklist).permit(
      :checklist_template_id,
      :plate_id,
      :placa_manual,
      checklist_responses_attributes: [:id, :checklist_item_id, :status, :comment, :photo]
    )
  end
end
