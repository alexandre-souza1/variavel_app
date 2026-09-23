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
    @drivers = params[:status] == "inactive" ? Driver.inactive : Driver.active
    @duplicate_counts = Employee.duplicate_registration_counts(@drivers.pluck(:matricula))
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
      Driver.transaction do
        CSV.foreach(file.path, headers: true, col_sep: ";", encoding: "ISO-8859-1:utf-8") do |row|
          Driver.create!(
            career_starts_on: row["inicio_cargo"],
            career_cargo: row["cargo"],
            career_recorded_by: current_user,
            matricula: row["matricula"],
            promax: row["promax"].to_s.strip.to_i.to_s,
            nome: row["nome"],
            cpf: row["cpf"],
            data_nascimento: row["data_nascimento"]
          )
        end

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
    @driver.career_recorded_by = current_user
    if @driver.save
      redirect_to @driver, notice: "Motorista criado com sucesso."
    else
      render :new
    end
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    @driver.errors.add(:base, error.message)
    render :new, status: :unprocessable_entity
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
    @driver.retire!
    redirect_to drivers_path, notice: "Motorista inativado com sucesso. O histórico foi preservado."
  end

  def destroy_all
    Driver.update_all(active: false, retired_at: Date.current, updated_at: Time.current)
    redirect_to drivers_path, notice: "Motoristas inativados com sucesso."
  end

  private

  def set_driver
    @driver = Driver.find(params[:id])
  end

  def driver_params
    params.require(:driver).permit(:career_starts_on, :career_cargo, :nome, :matricula, :promax, :cpf, :data_nascimento, :autonomy)
  end
end
