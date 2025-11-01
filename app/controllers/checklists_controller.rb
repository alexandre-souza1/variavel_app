class ChecklistsController < ApplicationController
  before_action :authenticate_user!, except: [:new, :create, :show]
  before_action :set_template, only: [:new]

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
    @template = ChecklistTemplate.find(checklist_params[:checklist_template_id])

    if user_signed_in?
      @checklist = current_user.checklists.new(checklist_params)
    else
      # cria o checklist sem usuário logado
      @checklist = Checklist.new(checklist_params)
      # define user_id como "usuário não registrado"
      # (criaremos um usuário padrão pra isso no passo 3)
      @checklist.user = User.find_by(email: "anon@system.local")
    end

    if @checklist.save
      redirect_to @checklist, notice: 'Checklist enviado com sucesso.'
    else
      @checklist.checklist_responses.each do |response|
        response.checklist_item ||= ChecklistItem.find(response.checklist_item_id)
      end
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
      :responsavel,
      :vehicle_model,
      :origin,
      :gas_state,
      :kilometer,
      checklist_responses_attributes: [:id, :checklist_item_id, :status, :comment, :photo]
    )
  end
end
