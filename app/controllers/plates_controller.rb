class PlatesController < ApplicationController
  def index
    @plates = Plate.all
  end

  def new
    @plate = Plate.new
  end

  def create
    @plate = Plate.new(plate_params)
    if @plate.save
      redirect_to plates_path, notice: "Placa criada com sucesso"
    else
      render :new
    end
  end

  def import
    if params[:file].present?
      Plate.import(params[:file])
      redirect_to plates_path, notice: "Placas importadas com sucesso"
    else
      redirect_to plates_path, alert: "Por favor, selecione um arquivo CSV"
    end
  end

  private

  def plate_params
    params.require(:plate).permit(:placa, :setor, :perfil, :tipo)
  end
end
