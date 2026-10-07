class OperatorsController < ApplicationController
  before_action :set_operator, only: %i[ show edit update destroy ]
  before_action :authenticate_user!
  before_action :only_admin, only: [:destroy_all]
  before_action :admin_or_supervisor, only: [:edit, :create, :update, :destroy, :import_csv]
  before_action :everyone_can_access, only: [:index, :show, :import]
  include OperatorsHelper

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

  # GET /operators or /operators.json
  def index
    redirect_to employees_path(employee_sector: 'az', cargo: 'operador', status: params[:status] == 'inactive' ? 'archived' : nil)
  end

  def import
  end

  def import_csv
    file = params[:file]

    if file.nil?
      redirect_to import_operators_path, alert: "Selecione um arquivo CSV para importar."
      return
    end

    require "csv"

    begin

      Operator.transaction do
        CSV.foreach(file.path, headers: true, col_sep: ";", encoding: "ISO-8859-1:utf-8") do |row|
          Operator.create!(
            career_starts_on: row["inicio_cargo"], career_recorded_by: current_user,
            matricula: row["matricula"],
            turno: turno_map[row["turno"]], # faz a conversão de letra para inteiro
            nome: row["nome"],
            cpf: row["cpf"],
            data_nascimento: row["data_nascimento"]
          )
        end
      end
      redirect_to operators_path, notice: "Operadores importados com sucesso!"
    rescue => e
      redirect_to import_operators_path, alert: "Erro ao importar: #{e.message}"
    end
  end

  # GET /operators/1 or /operators/1.json
  def show
    return redirect_to employee_path(@operator.employee) if @operator.employee
  end

  # GET /operators/new
  def new
    redirect_to new_employee_path(employee_sector: 'az', employee_cargo: 'operador')
  end

  # GET /operators/1/edit
  def edit
    return redirect_to edit_employee_path(@operator.employee) if @operator.employee
  end

  # POST /operators or /operators.json
  def create
    @operator = Operator.new(operator_params)
    @operator.career_recorded_by = current_user

    respond_to do |format|
      if @operator.save
        format.html { redirect_to @operator, notice: "Operator was successfully created." }
        format.json { render :show, status: :created, location: @operator }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @operator.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /operators/1 or /operators/1.json
  def update
    @operator.career_recorded_by = current_user
    respond_to do |format|
      if @operator.update(operator_params)
        format.html { redirect_to @operator, notice: "Operator was successfully updated." }
        format.json { render :show, status: :ok, location: @operator }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @operator.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /operators/1 or /operators/1.json
  def destroy
    @operator.retire!(user: current_user)

    respond_to do |format|
        format.html { redirect_to operators_path, status: :see_other, notice: "Operador inativado com sucesso. O histórico foi preservado." }
      format.json { head :no_content }
    end
  end

  def destroy_all
    Operator.transaction do
      people = Employee.active.where(id: EmployeeRole.where(sector: 'az', cargo: ['operador']).on(Date.current).select(:employee_id))
      people.find_each { |person| person.retire!(user: current_user, reason: 'Inativação em lote') }
      Operator.where(employee_id: nil).update_all(active: false, retired_at: Date.current, updated_at: Time.current)
    end
    redirect_to operators_path, notice: 'Colaboradores inativados. O histórico foi preservado.'
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_operator
      @operator = Operator.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def operator_params
      params.require(:operator).permit(:career_starts_on, :matricula, :nome, :cpf, :data_nascimento, :turno, :autonomy)
    end
end
