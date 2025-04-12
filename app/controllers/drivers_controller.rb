class DriversController < ApplicationController
  before_action :set_driver, only: %i[show edit update destroy]

  def index
    @drivers = Driver.all
  end

  def import
  end

  def import_csv
    file = params[:file]

    if file.nil?
      redirect_to import_drivers_path, alert: "Selecione um arquivo CSV para importar."
      return
    end

    require "csv"

    begin
      CSV.foreach(file.path, headers: true, col_sep: ";", encoding: "ISO-8859-1:utf-8") do |row|
        Driver.create!(
          matricula: row["matricula"],
          promax: row["promax"].to_s.rjust(5, "0"),
          nome: row["nome"],
          cpf: row["cpf"],
          data_nascimento: row["data_nascimento"]
        )
      end

      redirect_to drivers_path, notice: "Motoristas importados com sucesso!"
    rescue => e
      redirect_to import_drivers_path, alert: "Erro ao importar: #{e.message}"
    end
  end

  def show
  end

  def new
    @driver = Driver.new
  end

  def create
    @driver = Driver.new(driver_params)
    if @driver.save
      redirect_to @driver, notice: "Motorista criado com sucesso."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @driver.update(driver_params)
      redirect_to @driver, notice: "Motorista atualizado com sucesso."
    else
      render :edit
    end
  end

  def destroy
    @driver.destroy
    redirect_to drivers_path, notice: "Motorista apagado com sucesso."
  end

  private

  def set_driver
    @driver = Driver.find(params[:id])
  end

  def driver_params
    params.require(:driver).permit(:nome, :matricula, :promax, :cpf, :data_nascimento)
  end
end
