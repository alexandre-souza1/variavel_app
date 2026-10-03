class PcdsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_du!
  before_action :set_date

  def show
    @board = Pcd::Board.new(date: @date)
    @plan = @board.plan
    @plate_options = Plate.active.where(setor: 'ROTA').ordered.pluck(:placa).map { |plate| TimeOff::RoutingCsv.plate(plate) }.uniq
    @imports = @plan ? @plan.pcd_imports.includes(:user).order(id: :desc) : []
    @changes = @plan ? @plan.pcd_changes.includes(:user).order(id: :desc) : []
    @tab = %w[board imports history].include?(params[:tab]) ? params[:tab] : 'board'
    respond_to do |format|
      format.html
      format.pdf do
        raise TimeOff::UpdateDay::InvalidChange, 'Salve o PCD antes de imprimir.' unless @plan
        pdf = PcdPdf.new(@board).render
        @plan.pcd_changes.create!(user: current_user, action: 'print', reason: 'Impressão do PCD SALAS', details: { cars: @board.cars.select { |c| c['scheduled'] } })
        send_data pdf, filename: "PCD_SALAS_#{@date}.pdf", type: 'application/pdf', disposition: 'inline'
      end
    end
  rescue TimeOff::UpdateDay::InvalidChange => error
    redirect_to pcd_path(date: @date), alert: error.message
  end

  def preview_routing
    render json: Pcd::RoutingCsv.new(file: params[:file], board: Pcd::Board.new(date: @date)).preview
  rescue TimeOff::UpdateDay::InvalidChange => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def update
    attributes = params.require(:board).permit(:reason, :expected_revision, :routing_token,
      cars: %i[key plate scheduled operation helper_count driver helper1 helper2 room departure_time external_driver external_helper1 external_helper2 notes])
    Pcd::Save.call(date: @date, attributes: attributes, user: current_user)
    render json: { message: 'PCD salvo com histórico.' }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError, TimeOff::UpdateDay::Conflict => error
    render json: { error: error.message }, status: :conflict
  rescue TimeOff::UpdateDay::InvalidChange => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def require_du!
    head :forbidden unless current_user && !current_user.mechanical? && (current_user.admin? || current_user.sector_du?)
  end

  def set_date
    @date = params[:date].present? ? Date.iso8601(params[:date]) : Date.current
  rescue Date::Error
    if request.format.json?
      render json: { error: 'Data inválida.' }, status: :unprocessable_entity
    else
      redirect_to pcd_path, alert: 'Data inválida.'
    end
  end
end
