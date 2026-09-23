class EmployeesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_hr!
  before_action :set_employee, only: %i[show change_role close_period link_record revise_role delete_role]

  def index
    @employees = Employee.order(:nome).includes(:employee_roles)
    if params[:q].present?
      query = "%#{Employee.sanitize_sql_like(params[:q].strip)}%"
      @employees = @employees.where('nome ILIKE ? OR matricula ILIKE ?', query, query)
    end
    @employees = @employees.limit(200)
    @duplicate_counts = Employee.duplicate_registration_counts(@employees.map(&:matricula))
  end

  def new
    @employee = Employee.new
  end

  def create
    @employee = Employee.new(params.require(:employee).permit(:nome, :matricula, :cpf, :data_nascimento))
    Employee.transaction do
      @employee.save!
      @employee.change_role!(params.require(:employee_role).permit(:cargo, :promax, :starts_on, :reason), user: current_user)
    end
    redirect_to @employee, notice: 'Colaborador cadastrado.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end

  def show
    @duplicate_employees = Employee.with_career_history.where(matricula: @employee.matricula).where.not(id: @employee.id).includes(:employee_roles).order(:nome)
    @suggested_source = @duplicate_employees.find { |person| person.id.to_s == params[:source_employee_id].to_s && @employee.linkable_legacy_source?(person) }
    @roles = @employee.employee_roles.order(Arel.sql('starts_on DESC NULLS LAST'))
    @closings = @employee.variable_closings.order(year: :desc, month: :desc, revision: :desc)
  end

  def change_role
    @employee.change_role!(params.require(:employee_role).permit(:cargo, :promax, :starts_on, :reason), user: current_user)
    redirect_to @employee, notice: 'Movimentação registrada. Os cargos anteriores foram preservados.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    redirect_to @employee, alert: error.message
  end

  def delete_role
    role = @employee.employee_roles.find(params[:role_id])
    unless current_user.admin? && role.created_by_id == current_user.id
      return head :forbidden
    end
    @employee.delete_last_role!(role.id, user: current_user)
    redirect_to @employee, notice: 'Movimentação excluída e cargo anterior restaurado. Fechamentos registrados foram preservados; revise-os se necessário.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    redirect_to @employee, alert: error.message
  end

  def revise_role
    @employee.revise_role!(params[:role_id], params.require(:employee_role).permit(:cargo, :promax, :starts_on, :reason), user: current_user)
    redirect_to @employee, notice: 'Correção registrada. Fechamentos existentes mantêm os resultados; gere uma revisão se necessário.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    redirect_to @employee, alert: error.message
  end

  def close_period
    closing = VariableClosing.capture!(employee: @employee, user: current_user,
      year: params[:year].to_i, month: params[:month].to_i, reason: params[:reason])
    redirect_to @employee, notice: "Fechamento registrado, revisão #{closing.revision}."
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError, Date::Error => error
    redirect_to @employee, alert: error.message
  end

  # Connect an existing operational record without deleting its historical identity.
  # Both people and all career dates must be reviewed before merging.
  def link_record
    source = Employee.find(params[:source_employee_id])
    raise EmployeeRole::HistoryError, 'Selecione outro cadastro.' if source == @employee
    Employee.transaction do
      [@employee, source].sort_by(&:id).each(&:lock!)
      Employee.connection.execute("SELECT pg_advisory_xact_lock(739231200)")
      same_cpf = @employee.cpf.present? && source.cpf.present? && @employee.cpf.gsub(/\D/, '') == source.cpf.gsub(/\D/, '')
      raise EmployeeRole::HistoryError, 'Os cadastros devem ter o mesmo CPF para confirmar a identidade.' unless same_cpf
      raise EmployeeRole::HistoryError, 'O cadastro de origem precisa ter apenas a vigência legada, ainda não movimentada.' unless source.employee_roles.size == 1 && source.employee_roles.first.legacy?
      role = source.employee_roles.first
      original = role.attributes
      role.destroy!
      @employee.change_role!({ cargo: role.cargo, promax: role.promax, starts_on: params[:starts_on], reason: params[:reason] }, user: current_user)
      source.drivers.update_all(employee_id: @employee.id)
      source.ajudantes.update_all(employee_id: @employee.id)
      source.update!(active: false)
      @employee.employee_career_events.create!(user: current_user, details: { action: 'link_record', source: source.attributes, original_role: original })
    end
    redirect_to @employee, notice: 'Cadastro operacional vinculado. O histórico selecionado passa a identificar a pessoa.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    redirect_to @employee, alert: error.message
  end

  private

  def set_employee
    @employee = Employee.find(params[:id])
  end

  def require_hr!
    return if current_user.admin? || current_user.supervisor? || current_user.sector_hr?
    redirect_to root_path, alert: 'Acesso restrito ao RH, supervisão e administração.'
  end
end
