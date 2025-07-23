class AutonomiesController < ApplicationController
  before_action :set_plates, only: [:new, :create]

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

  private

  def set_plates
    @plates = Plate.all.pluck(:placa) # ou o nome correto do campo
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
