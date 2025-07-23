class AutonomiesController < ApplicationController
  before_action :set_plates, only: [:new, :create]
  before_action :set_autonomy, only: [:destroy]

  def index
    @autonomies = if params[:search].present?
                    # Busca por matrícula para usuários não admin
                    Autonomy.includes(:user)
                           .where(registration: params[:search])
                           .order(created_at: :desc)
                           .page(params[:page])
                  elsif current_user&.admin?
                    # Visão completa para administradores
                    Autonomy.includes(:user)
                           .order(created_at: :desc)
                           .page(params[:page])
                  else
                    # Retorna vazio para usuários não logados sem busca
                    Autonomy.none.page(params[:page])
                  end
  end

  def new
    @autonomy = Autonomy.new
  end

  def create
    @autonomy = Autonomy.new(autonomy_params)
    set_user_for_autonomy

    if @autonomy.save
      redirect_to root_path, notice: "Registro criado com sucesso!"
    else
      render :new
    end
  end

  def destroy
    @autonomy.destroy
    redirect_to autonomies_path, notice: "Registro apagado com sucesso."
  end

  def check_registration
  registration = params[:registration]
  # Aqui você deve implementar a lógica para verificar o tipo de usuário
  # Exemplo simplificado:
  user = User.find_by(registration: registration)

  if user
    render json: { user_type: user.user_type } # Supondo que user_type seja 'Driver' ou 'Operator'
  else
    render json: { user_type: nil }
  end
  end

  def plates
    equipment_type = params[:equipment_type]

    # Busca as placas na tabela plates filtrando pelo tipo de equipamento
    plates = Plate.where(tipo: equipment_type).pluck(:placa) # assumindo que a coluna se chama 'placa'

    render json: plates
  end

  private

  def set_autonomy
    @autonomy = Autonomy.find(params[:id])
  end

  def set_plates
    # Inicialmente vazio, será preenchido via AJAX quando selecionar o equipment_type
    @plates = []
  end

  def autonomy_params
    params.require(:autonomy).permit(:registration, :equipment_type, :service_type, :plate, :report, :evidence)
  end

  def set_user_for_autonomy
    registration = params[:autonomy][:registration]
    user = Driver.find_by(matricula: registration) || Operator.find_by(matricula: registration)

    if user
      @autonomy.user = user
      @autonomy.user_type = user.class.name
    else
      flash.now[:alert] = "Matrícula não encontrada em Driver ou Operator"
      render :new and return
    end
  end
end
