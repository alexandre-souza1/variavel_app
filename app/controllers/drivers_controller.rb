class DriversController < ApplicationController
  before_action :set_driver, only: %i[show edit update destroy]
  before_action :authenticate_user!
  before_action :only_admin, only: [:destroy_all]
  before_action :admin_or_supervisor, only: [:edit, :create, :update, :destroy, :import_csv]
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
    redirect_to employees_path(employee_sector: 'du', cargo: 'motorista', status: params[:status] == 'inactive' ? 'archived' : nil)
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
    return redirect_to employee_path(@driver.employee) if @driver.employee
  end

  def new
    redirect_to new_employee_path(employee_sector: 'du', employee_cargo: 'motorista')
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
    return redirect_to edit_employee_path(@driver.employee) if @driver.employee
  end

  def update
    @driver.career_recorded_by = current_user
    if @driver.update(driver_params)
      redirect_to @driver, notice: "Motorista atualizado com sucesso."
    else
      render :edit
    end
  end

  def destroy
    @driver.retire!(user: current_user)
    redirect_to drivers_path, notice: "Motorista inativado com sucesso. O histórico foi preservado."
  end

  def destroy_all
    Driver.transaction do
      people = Employee.active.where(id: EmployeeRole.where(sector: 'du', cargo: %w[motorista van]).on(Date.current).select(:employee_id))
      people.find_each { |person| person.retire!(user: current_user, reason: 'Inativação em lote') }
      Driver.where(employee_id: nil).update_all(active: false, retired_at: Date.current, updated_at: Time.current)
    end
    redirect_to drivers_path, notice: 'Colaboradores inativados. O histórico foi preservado.'
  end

  private

  def set_driver
    @driver = Driver.find(params[:id])
  end

  def driver_params
    params.require(:driver).permit(:career_starts_on, :career_cargo, :nome, :matricula, :promax, :cpf, :data_nascimento, :autonomy)
  end
end
