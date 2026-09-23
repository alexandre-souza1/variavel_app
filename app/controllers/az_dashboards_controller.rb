class AzDashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_az_dashboard_access!

  def show
    anchor = Date.current.day > 18 ? Date.current.next_month : Date.current
    @mes = params[:mes].presence&.to_i || anchor.month
    @ano = params[:ano].presence&.to_i || anchor.year
    reference = Date.new(@ano, @mes, 1)
    raise ArgumentError unless (2000..2100).cover?(@ano)

    @periodo_tipo = params[:periodo_tipo].presence || "mes"
    raise ArgumentError unless %w[mes primeira_quinzena segunda_quinzena].include?(@periodo_tipo)
    @turno = params[:turno].presence
    raise ArgumentError if @turno && !%w[0 1 2].include?(@turno)

    @periodo_inicio = reference.prev_month.change(day: 19)
    @periodo_fim = reference.change(day: 18)
    if @periodo_tipo == "primeira_quinzena"
      @periodo_fim = @periodo_inicio + 14.days
    elsif @periodo_tipo == "segunda_quinzena"
      @periodo_inicio += 15.days
    end
    @dashboard = AzDashboardService.new(start_date: @periodo_inicio, end_date: @periodo_fim, turno: @turno&.to_i).call
  rescue ArgumentError
    redirect_to dashboard_az_path, alert: "Selecione um período e turno válidos."
  end

  private

  def require_az_dashboard_access!
    return if current_user&.can_access_az_dashboard?

    redirect_to root_path, alert: "Acesso restrito ao dashboard do Armazém"
  end
end
