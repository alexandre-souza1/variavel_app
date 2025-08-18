class FuelConsumptionsController < ApplicationController
  before_action :authenticate_user! # se você usa Devise

  def index
    @fuel_consumptions = FuelConsumption.order(created_at: :desc)
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
