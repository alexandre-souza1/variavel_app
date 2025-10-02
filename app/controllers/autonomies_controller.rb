class AutonomiesController < ApplicationController
  before_action :set_plates, only: [:new, :create]
  before_action :set_autonomy, only: [:destroy]

  def index
    all_autonomies = if params[:search].present?
                        Autonomy.includes(:user)
                                .where(registration: params[:search])
                                .order(created_at: :desc)
                      elsif current_user&.admin?
                        Autonomy.includes(:user)
                                .order(created_at: :desc)
                      else
                        Autonomy.none
                      end

    pagination = helpers.paginate_records(all_autonomies, params, per_page: 15)

    @autonomies = pagination[:records]
    @current_page = pagination[:current_page]
    @total_pages = pagination[:total_pages]
    @total_autonomies = all_autonomies.count

    # últimas placas distintas (só para operador, sem busca ativa)
    if !current_user&.admin? && params[:search].blank?
      @recent_autonomies = Autonomy
                            .select("DISTINCT ON (plate) autonomies.*")
                            .order("plate, created_at DESC")
                            .includes(:user)
                            .limit(5)
    end
  end


  def new
    @autonomy = Autonomy.new
  end

  def show
    @autonomy = Autonomy.find(params[:id])
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

    # Verifica primeiro em Driver
    driver = Driver.find_by(matricula: registration)
    if driver
      render json: {
        valid: driver.autonomy,
        user_type: 'Driver',
        has_autonomy: driver.autonomy
      }
      return
    end

    # Se não encontrou em Driver, verifica em Operator
    operator = Operator.find_by(matricula: registration)
    if operator
      render json: {
        valid: operator.autonomy,
        user_type: 'Operator',
        has_autonomy: operator.autonomy
      }
      return
    end

    # Se não encontrou em nenhum dos dois
    render json: {
      valid: false,
      user_type: nil,
      has_autonomy: false
    }
  end

  def plates
    equipment_type = params[:equipment_type]
    plates = Plate.where(tipo: equipment_type).pluck(:placa)
    render json: plates
  end

  def export_csv
    @autonomies = Autonomy.all

    respond_to do |format|
      format.csv do
      csv_content = "\uFEFF" + generate_csv
      send_data csv_content,
                filename: "registros-autonomia-#{Date.today}.csv",
                type: 'text/csv; charset=utf-8'
      end
    end
  end

  def dashboard
    begin
      @from_date = params[:from_date].present? ? Date.parse(params[:from_date]) : 30.days.ago.to_date
      @to_date   = params[:to_date].present? ? Date.parse(params[:to_date]) : Date.today
    rescue ArgumentError
      @from_date = 30.days.ago.to_date
      @to_date = Date.today
    end

    @from_date = params[:from_date].present? ? Date.parse(params[:from_date]) : 30.days.ago.to_date
    @to_date   = params[:to_date].present? ? Date.parse(params[:to_date]) : Date.today

    @equipment_type = params[:equipment_type]
    @service_type   = params[:service_type]
    @user_type      = params[:user_type]

    @autonomies = Autonomy.includes(:user)
                          .where(created_at: @from_date.beginning_of_day..@to_date.end_of_day)

    @autonomies = @autonomies.where(equipment_type: @equipment_type) if @equipment_type.present?
    @autonomies = @autonomies.where(service_type: @service_type) if @service_type.present?
    @autonomies = @autonomies.where(user_type: @user_type) if @user_type.present?

    # Estatísticas
    @total_registros = @autonomies.count
    @por_equipamento = @autonomies.group(:equipment_type).count
    @por_servico     = @autonomies.group(:service_type).count
    @por_usuario     = @autonomies.group(:user_type).count
    @por_dia         = @autonomies.group_by_day(:created_at).count

    counts = @autonomies.group([:user_type, :user_id]).count

    @por_colaborador = counts.transform_keys do |user_type, user_id|
      user_type.constantize.find(user_id).nome
    end
  end


  private

  def set_autonomy
    @autonomy = Autonomy.find(params[:id])
  end

  def set_plates
    @plates = []
  end

  def generate_csv
    CSV.generate(col_sep: ';', force_quotes: true, encoding: 'UTF-8') do |csv|
      # Cabeçalho
      csv << ["ID", "Matrícula", "Nome", "Equipamento", "Tipo de Serviço", "Placa", "Relato", "Data"]

      # Dados
      @autonomies.each do |a|
        csv << [
          a.id,
          a.registration,
          a.user&.nome || "N/A",
          a.equipment_type,
          a.service_type,
          a.plate,
          a.report,
          I18n.l(a.created_at, format: :short)
        ]
      end
    end
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
