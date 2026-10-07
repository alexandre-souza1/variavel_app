class EmployeesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_access!
  before_action :set_sector_context
  before_action :require_hr!, except: %i[index show assign_group]
  before_action :set_employee, only: %i[show edit update retire reactivate change_role close_period recalculate_closing link_record revise_role delete_role revise_closing assign_group]
  before_action :require_role_sector!, only: %i[create change_role revise_role close_period]

  def index
    @archived_view = params[:status].to_s == 'archived'
    scope = visible_employees
    scope = scope.in_current_or_last_sector(@sector_filter) if @sector_filter && current_user.employee_sectors.many?
    @employees = (@archived_view ? scope.archived : scope.active).order(:nome).includes(:employee_roles)
    @archived_count = scope.archived.count
    if params[:cargo].present? || params[:turno].present?
      roles = EmployeeRole.on(Date.current)
      roles = roles.where(sector: @sector_filter) if @sector_filter
      roles = roles.where(cargo: params[:cargo]) if params[:cargo].present?
      roles = roles.where(turno: params[:turno]) if params[:turno].present?
      @employees = @employees.where(id: roles.select(:employee_id))
    end
    if params[:q].present?
      query = "%#{Employee.sanitize_sql_like(params[:q].strip)}%"
      @employees = @employees.where('nome ILIKE ? OR matricula ILIKE ?', query, query)
    end
    @employees = @employees.limit(200)
    @duplicate_counts = visible_employees.duplicate_registration_counts(@employees.map(&:matricula))
    @schedule = TimeOffSchedule.order(:id).first
    @group_memberships = TimeOff::GroupRoster.memberships(schedule: @schedule, date: Date.current, employee_ids: @employees.map(&:id))
  end

  def assign_group
    return head :forbidden unless current_user.can_manage_time_off? && @employee.eligible_for?(:time_off)
    schedule = TimeOffSchedule.order(:id).first!
    attributes = params.require(:membership).permit(:group_code, :starts_on, :fixed_weekday, :standard_operation)
    TimeOff::AssignGroup.call(schedule: schedule, person: @employee, user: current_user,
      group_code: attributes[:group_code], starts_on: Date.iso8601(attributes[:starts_on].to_s),
      fixed_weekday: attributes[:fixed_weekday].presence&.to_i, standard_operation: attributes[:standard_operation])
    redirect_to employees_path(employee_navigation), notice: 'Grupo salvo. As vigências anteriores foram preservadas.'
  rescue ActiveRecord::RecordInvalid, TimeOff::UpdateDay::InvalidChange, Date::Error => error
    redirect_to employees_path(employee_navigation), alert: error.message
  end

  def new
    @employee = Employee.new
  end

  def edit; end

  def update
    Employees::Registry.update!(@employee, attributes: identity_params, user: current_user, reason: params[:reason])
    redirect_to employee_destination(@employee), notice: 'Dados do colaborador atualizados em todos os módulos.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    flash.now[:alert] = error.message
    render :edit, status: :unprocessable_entity
  end

  def retire
    @employee.retire!(user: current_user, reason: params[:reason].presence || 'Inativação pelo RH')
    redirect_to employee_destination(@employee), notice: 'Colaborador inativado. O histórico foi preservado.'
  end

  def reactivate
    Employees::Registry.update!(@employee, attributes: { active: true, retired_at: nil }, user: current_user,
      reason: params[:reason].presence || 'Reativação pelo RH')
    redirect_to employee_destination(@employee), notice: 'Colaborador reativado.'
  end

  def create
    @employee = Employee.new(identity_params)
    initial_role = role_params
    initial_role[:reason] = initial_role[:reason].presence || 'Cadastro inicial'
    Employee.transaction do
      @employee.save!
      @employee.change_role!(initial_role, user: current_user)
    end
    redirect_to employee_destination(@employee), notice: 'Colaborador cadastrado.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end

  def show
    @duplicate_employees = visible_employees.with_career_history.where(matricula: @employee.matricula).where.not(id: @employee.id).includes(:employee_roles).order(:nome)
    @suggested_source = @duplicate_employees.find { |person| person.id.to_s == params[:source_employee_id].to_s && @employee.linkable_legacy_source?(person) }
    @roles = @employee.employee_roles.where(sector: current_user.employee_sectors).order(Arel.sql('starts_on DESC NULLS LAST'))
    latest_role = @roles.first
    @next_cargos = latest_role ? EmployeeRole.next_cargos(latest_role.cargo, sector: latest_role.sector) : EmployeeRole::CARGOS.values
    all_closings = visible_closings.order(year: :desc, month: :desc, revision: :desc).to_a
    @closings = all_closings.group_by { |closing| [closing.sector, closing.year, closing.month] }.values.map(&:first)
    @closing_cargos = @closings.flat_map { |closing| closing.result.fetch('groups', {}).keys }.select { |cargo| EmployeeRole::CARGOS.value?(cargo) }.uniq
    @cargo_filter = params[:cargo].presence
  end

  def change_role
    @employee.change_role!(role_params, user: current_user)
    redirect_to employee_destination(@employee), notice: 'Movimentação registrada. Os cargos anteriores foram preservados.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    redirect_to employee_destination(@employee), alert: error.message
  end

  def delete_role
    role = @employee.employee_roles.where(sector: current_user.employee_sectors).find(params[:role_id])
    unless current_user.admin? && role.created_by_id == current_user.id
      return head :forbidden
    end
    @employee.delete_last_role!(role.id, user: current_user)
    redirect_to employee_destination(@employee), notice: 'Movimentação excluída e cargo anterior restaurado. Fechamentos registrados foram preservados; revise-os se necessário.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    redirect_to employee_destination(@employee), alert: error.message
  end

  def revise_role
    @employee.employee_roles.where(sector: current_user.employee_sectors).find(params[:role_id])
    @employee.revise_role!(params[:role_id], role_params, user: current_user)
    redirect_to employee_destination(@employee), notice: 'Correção registrada. Fechamentos existentes mantêm os resultados; gere uma revisão se necessário.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    redirect_to employee_destination(@employee), alert: error.message
  end

  def close_period
    closing = VariableClosing.capture!(employee: @employee, user: current_user,
      year: params[:year].to_i, month: params[:month].to_i, reason: params[:reason], sector: params[:employee_sector].presence || 'du')
    redirect_to employee_destination(@employee), notice: "Fechamento registrado, revisão #{closing.revision}."
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError, Date::Error => error
    redirect_to employee_destination(@employee), alert: error.message
  end

  def recalculate_closing
    closing = visible_closings.find(params[:closing_id])
    reason = params[:reason].presence || 'Recalculado após correção do histórico de cargos'
    revision = VariableClosing.capture!(employee: @employee, user: current_user,
      year: closing.year, month: closing.month, reason: reason, sector: closing.sector)
    redirect_to employee_destination(@employee), notice: "Revisão #{revision.revision} criada com o histórico atual."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, EmployeeRole::HistoryError, Date::Error => error
    redirect_to employee_destination(@employee), alert: error.message
  end

  def revise_closing
    closing = visible_closings.find(params[:closing_id])
    closing.revise_cargo!(from_cargo: params[:from_cargo], to_cargo: params[:to_cargo], user: current_user, reason: params[:reason])
    revision = VariableClosing.where(employee: @employee, sector: closing.sector, year: closing.year, month: closing.month).maximum(:revision)
    redirect_to employee_destination(@employee), notice: "Revisão #{revision} registrada. A revisão anterior foi preservada."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, EmployeeRole::HistoryError => error
    redirect_to employee_destination(@employee), alert: error.message
  end

  # Connect an existing operational record without deleting its historical identity.
  # Both people and all career dates must be reviewed before merging.
  def link_record
    requested_record = visible_employees.find(params[:source_employee_id])
    return head :forbidden if [@employee, requested_record].any? { |person| person.employee_roles.where.not(sector: current_user.employee_sectors).exists? }
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
      merged_closings = destination.merge_variable_closings_from!(source, user: current_user)
      source.drivers.update_all(employee_id: destination.id)
      source.ajudantes.update_all(employee_id: destination.id)
      source.operators.update_all(employee_id: destination.id)
      source.az_ajudantes.update_all(employee_id: destination.id)
      TimeOffMembership.where(employee_id: source.id).update_all(employee_id: destination.id)
      [WmsTask, AzRvPoint, AzRvTask, AzRvOnDemandActivity].each do |model|
        model.where(employee_id: source.id).update_all(employee_id: destination.id)
      end
      source.employee_names.each { |entry| Employees::Registry.remember_name!(destination, entry.name) }
      source.update!(active: false)
      EmployeeName.where(employee_id: source.id).delete_all
      destination.update!(registration_aliases: (destination.registration_aliases + source.registration_aliases).uniq)
      Employees::Registry.synchronize!(destination)
      destination.employee_career_events.create!(user: current_user, details: {
        action: 'link_record', source: source.attributes, original_role: original,
        requested_from_employee_id: @employee.id, destination_employee_id: destination.id,
        source_employee_id: source.id, merged_closings: merged_closings
      })
    end
    redirect_to employee_destination(@destination), notice: 'Cadastro operacional vinculado. O histórico foi consolidado no cadastro principal.'
  rescue ActiveRecord::RecordInvalid, EmployeeRole::HistoryError => error
    redirect_to employee_destination(@employee), alert: error.message
  end

  private

  def set_sector_context
    allowed = current_user.employee_sectors
    @sector_filter = allowed.one? ? allowed.first : params[:employee_sector].presence_in(allowed)
  end

  def employee_navigation
    context = params.permit(:q, :cargo, :turno, :status).to_h.symbolize_keys
    context[:employee_sector] = @sector_filter if @sector_filter
    context
  end
  helper_method :employee_navigation

  def visible_employees
    current_user.employee_sectors.size == 2 ? Employee.all : Employee.in_current_or_last_sector(current_user.employee_sectors)
  end

  def visible_closings
    @employee.variable_closings.where(sector: current_user.employee_sectors)
  end

  def require_role_sector!
    sector = action_name == 'close_period' ? (params[:employee_sector].presence || 'du') : (params.dig(:employee_role, :sector).presence || 'du')
    head :forbidden unless current_user.employee_sectors.include?(sector)
  end

  def employee_destination(employee)
    visible_employees.exists?(employee.id) ? employee_path(employee, employee_navigation) : employees_path(employee_navigation)
  end

  def identity_params
    fields = %i[nome matricula cpf data_nascimento]
    fields << :operational_autonomy if action_name == 'update'
    params.require(:employee).permit(*fields)
  end

  def role_params
    params.require(:employee_role).permit(:sector, :cargo, :promax, :turno, :starts_on, :reason)
  end

  def require_access!
    redirect_to root_path, alert: 'Acesso restrito à gestão de colaboradores.' unless current_user.can_view_employees?
  end

  def set_employee
    @employee = Employee.find(params[:id])
    head :forbidden unless visible_employees.exists?(@employee.id)
  end

  def require_hr!
    return if current_user.can_manage_employees?
    redirect_to root_path, alert: 'Acesso restrito ao RH, supervisão e administração.'
  end
end
