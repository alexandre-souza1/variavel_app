class FuelConsumptionsController < ApplicationController
  before_action :authenticate_user! # se você usa Devise

  def index
    closing = Date.current.day <= 20 ? Date.current : Date.current.next_month
    @from = params[:from].present? ? Date.iso8601(params[:from]) : closing.prev_month.change(day: 21)
    @to = params[:to].present? ? Date.iso8601(params[:to]) : closing.change(day: 20)
    if @to < @from || (@to - @from).to_i > 366
      raise ArgumentError, 'Selecione um intervalo de até 366 dias, com início anterior ao fim.'
    end
    @report = Gasola::TeamReport.new(from: @from, to: @to, registration: params[:registration], plate: params[:plate], fuel: params[:fuel])
    @totals = @report.totals
    @emissions = @report.emissions
    @page = [params[:page].to_i, 1].max
    @pages = [(@report.records.size / 50.0).ceil, 1].max
    @page = [@page, @pages].min
    @supplies = @report.records.slice((@page - 1) * 50, 50) || []
    @legacy_consumptions = FuelConsumption.order(created_at: :desc).limit(100)
  rescue Date::Error, ArgumentError
    redirect_to fuel_consumptions_path, alert: 'Informe datas válidas, em ordem, com intervalo de até 366 dias.'
  end

  def new
  end

  def create
    if params[:file].present? && params[:period].present?
      FuelConsumption.import(params[:file], period: params[:period])
      redirect_to fuel_consumptions_path, notice: "Relatório importado com sucesso!"
    else
      redirect_to new_fuel_consumption_path, alert: "Selecione um arquivo e informe o período."
    end
  end
end
