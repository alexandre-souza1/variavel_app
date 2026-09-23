class EmployeesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_hr!
  before_action :set_employee, only: %i[show change_role close_period link_record revise_role delete_role revise_closing]

  def index
    @archived_view = params[:status].to_s == 'archived'
    @employees = (@archived_view ? Employee.archived : Employee.active).order(:nome).includes(:employee_roles)
    @archived_count = Employee.archived.count
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
    latest_role = @roles.first
    @next_cargos = latest_role ? EmployeeRole.next_cargos(latest_role.cargo) : EmployeeRole::CARGOS.values
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

  def revise_closing
    closing = @employee.variable_closings.find(params[:closing_id])
    closing.revise_cargo!(from_cargo: params[:from_cargo], to_cargo: params[:to_cargo], user: current_user, reason: params[:reason])
    revision = VariableClosing.where(employee: @employee, year: closing.year, month: closing.month).maximum(:revision)
    redirect_to @employee, notice: "Revisão #{revision} registrada. A revisão anterior foi preservada."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, EmployeeRole::HistoryError => error
    redirect_to @employee, alert: error.message
  end

  # Connect an existing operational record without deleting its historical identity.
  # Both people and all career dates must be reviewed before merging.
  def link_record
    requested_record = Employee.find(params[:source_employee_id])
    @requested_record = requested_record
    @invert_positions = ActiveModel::Type::Boolean.new.cast(params[:invert_positions])
    @destination, @source = @employee.resolve_link_pair(requested_record, invert: @invert_positions)

    if request.get?
      @destination_roles = @destination.employee_roles.order(Arel.sql('starts_on ASC NULLS FIRST'))
      @source_roles = @source.employee_roles.order(Arel.sql('starts_on ASC NULLS FIRST'))
      @destination_maps_count = @destination.maps.count
      @source_maps_count = @source.maps.count
      @destination_closings_count = @destination.variable_closings.count
      @source_closings_count = @source.variable_closings.count
      @destination_closings = @destination.variable_closings.order(year: :desc, month: :desc, revision: :desc).limit(3)
      @source_closings = @source.variable_closings.order(year: :desc, month: :desc, revision: :desc).limit(3)
      return render :link_record
    end

    Employee.transaction do
      [@employee, requested_record].sort_by(&:id).each(&:lock!)
      Employee.connection.execute("SELECT pg_advisory_xact_lock(739231200)")
      @destination, @source = @employee.resolve_link_pair(requested_record, invert: @invert_positions)
      destination = @destination
      source = @source
      role = source.employee_roles.first
      original = role.attributes
      role.destroy!
      destination.merge_linked_role!(original, starts_on: params[:starts_on], reason: params[:reason], user: current_user)
      merged_closings = destination.merge_variable_closings_from!(source)
      source.drivers.update_all(employee_id: destination.id)
      source.ajudantes.update_all(employee_id: destination.id)
      source.update!(active: false)
      destination.employee_career_events.create!(user: current_user, details: {
        action: 'link_record', source: source.attributes, original_role: original,
        requested_from_employee_id: @employee.id, destination_employee_id: destination.id,
        source_employee_id: source.id, merged_closings: merged_closings
      })
    end
    redirect_to @destination, notice: 'Cadastro operacional vinculado. O histórico foi consolidado no cadastro principal.'
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
