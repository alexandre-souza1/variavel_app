class DriversController < ApplicationController
  before_action :set_driver, only: %i[show edit update destroy]
  before_action :authenticate_user!
  before_action :only_admin, only: [:destroy_all]
  before_action :admin_or_supervisor, only: [:edit, :create, :update, :destroy]
  before_action :everyone_can_access, only: [:index, :show, :import]

  def only_admin
    redirect_back fallback_location: root_path, alert: "Acesso negado" unless current_user.admin?
  end

  def admin_or_supervisor
    unless current_user.admin? || current_user.supervisor?
      redirect_back fallback_location: root_path, alert: "Acesso negado"
    end
  end

  def everyone_can_access
    unless current_user.admin? || current_user.supervisor? || current_user.user?
      redirect_back fallback_location: root_path, alert: "Acesso negado"
    end
  end

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
          promax: row["promax"].to_s.strip.to_i.to_s,
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

  def destroy_all
    Driver.delete_all
    redirect_to drivers_path, notice: "Todos os Motoristas foram apagados com sucesso."
  end

  private

  def set_driver
    @driver = Driver.find(params[:id])
  end

  def driver_params
    params.require(:driver).permit(:nome, :matricula, :promax, :cpf, :data_nascimento)
  end
end
