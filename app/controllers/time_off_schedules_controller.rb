class TimeOffSchedulesController < ApplicationController
  CALENDAR_PAGE_SIZE = 12
  CALENDAR_PAGE_SIZES = [12, 24, 48].freeze
  before_action :authenticate_user!
  before_action :require_access!
  before_action :require_editor!, only: %i[assign_group ignore_suggestion revise_membership delete_membership update_day update_rotation update_coverage preview_routing create_vacation cancel_vacation]
  before_action :set_schedule

  def show
    return redirect_to pcd_path(date: params[:date]) if params[:tab] == 'coverage'
    @tab = %w[calendar day extras history].include?(params[:tab]) ? params[:tab] : 'calendar'
    @settings_open = params[:settings] == '1' || params[:tab] == 'groups'
    @date = params[:date].present? ? Date.iso8601(params[:date]) : Date.current
    @month = params[:month].present? ? Date.iso8601("#{params[:month]}-01") : @date.beginning_of_month
    @date = @month if @date.beginning_of_month != @month
    @month_days = (@month..@month.end_of_month).to_a
    roster = TimeOff::GroupRoster.new(schedule: @schedule, date: @date)
    @unassigned_people = roster.suggestions
    @editable_memberships = TimeOff::GroupRoster.editable_memberships(schedule: @schedule, date: @date)
    @days = @month_days
    prepare_calendar_days if @tab == 'calendar'
    first, last = @month, @month.end_of_month
    @memberships = @schedule.time_off_memberships.with_active_people.during(first, last).includes(driver: { employee: :employee_roles }, ajudante: { employee: :employee_roles }).to_a
      .sort_by { |member| [member.group_code, member.role(@date), member.person.nome.to_s, member.id] }
    @availability = TimeOff::Availability.new(schedule: @schedule, first: first, last: last)
    monthly_members = @memberships.select { |m| m.starts_on <= @month.end_of_month && (!m.ends_on || m.ends_on >= @month) }
    @extras = TimeOff::Extras.new(schedule: @schedule, month: @month, members: monthly_members, availability: @availability)
    @role = %w[driver helper].include?(params[:role]) ? params[:role] : nil
    @group = TimeOffSchedule::GROUPS.include?(params[:group]) ? params[:group] : nil
    @name_query = params[:name].to_s.squish
    @per_page = CALENDAR_PAGE_SIZES.map(&:to_s).include?(params[:per_page]) ? params[:per_page].to_i : CALENDAR_PAGE_SIZE
    normalized_query = normalize_name(@name_query)
    @visible_memberships = @memberships.select do |member|
      (!@role || member.role(@date) == @role) && (!@group || member.group_code == @group) &&
        (normalized_query.empty? || normalize_name(member.person.nome).include?(normalized_query))
    end
    paginate_calendar if @tab == 'calendar'
    @daily = @visible_memberships.select { |member| @schedule.base_status(member, @date) }.group_by { |member| status_for(member, @date) == 'vacation' ? 'unavailable' : status_for(member, @date) } if @tab == 'day'
    if @tab == 'day'
      @coverage = TimeOff::Coverage.new(schedule: @schedule, date: @date)
      @demand = TimeOff::Demand.new(@coverage).metrics if @coverage.dimensioning
    end
    @changes = @schedule.time_off_changes.where(date: @date).includes(:user, time_off_membership: [:driver, :ajudante]).order(id: :desc).limit(30) if @tab == 'history'
    if can_edit?
      @correction_memberships = @schedule.time_off_memberships.with_active_people.includes(:employee, driver: :employee, ajudante: :employee).sort_by { |m| [m.person.nome.to_s, m.starts_on, m.id] }
      @pilot_pending = TimeOff::PilotSetup.pending(@schedule)
      @vacations = @schedule.time_off_vacations.active.during(@month, @month.end_of_month).includes(time_off_membership: [{ driver: :employee }, { ajudante: :employee }]).order(:starts_on).select { |v| v.time_off_membership.active_person? }
      @vacation_people = @schedule.time_off_memberships.with_active_people.on(@date).includes(:driver, :ajudante).sort_by { |m| m.person.nome }
      @people_options = Employee.active.in_sector('du', date: @date).includes(:employee_roles).order(:nome).map do |person|
        role = person.role_on(@date)
        ["#{role.label} · #{person.nome} · #{role.promax}", "employee:#{person.id}"]
      end
      @people_options += TimeOff::People.active_records(Driver, date: @date).where(employee_id: nil).order(:nome).map { |p| ["Motorista · #{p.nome} · #{p.promax}", "driver:#{p.id}"] }
      @people_options += TimeOff::People.active_records(Ajudante, date: @date).where(employee_id: nil).order(:nome).map { |p| ["Ajudante · #{p.nome} · #{p.promax}", "helper:#{p.id}"] }
    end
  rescue Date::Error
    redirect_to time_off_schedule_path, alert: 'Data inválida.'
  end

  def assign_group
    attributes = params.require(:membership).permit(:person, :group_code, :starts_on, :fixed_weekday, :pilot_key, :standard_operation, :new_change)
    type, id = attributes[:person].to_s.split(':', 2)
    klass = { 'employee' => Employee, 'driver' => Driver, 'helper' => Ajudante }[type]
    raise TimeOff::UpdateDay::InvalidChange, 'Selecione um motorista ou ajudante.' unless klass
    date = Date.iso8601(attributes[:starts_on].to_s)
    person = klass.find(id)
    @schedule.with_lock do
      if @schedule.time_off_memberships.for_person(person).exists? && attributes[:new_change] != '1'
        raise TimeOff::UpdateDay::InvalidChange, 'Este colaborador já possui vigência. Use Corrigir vigência; para registrar uma nova mudança, marque a opção correspondente.'
      end
      TimeOff::AssignGroup.call(schedule: @schedule, person: person, group_code: attributes[:group_code], starts_on: date, user: current_user, fixed_weekday: attributes[:fixed_weekday].presence&.to_i, pilot_key: attributes[:pilot_key], standard_operation: attributes[:standard_operation])
    end
    redirect_to group_assignment_path(date: date), notice: 'Grupo salvo. As vigências anteriores foram preservadas.'
  rescue ActiveRecord::RecordInvalid, TimeOff::UpdateDay::InvalidChange, Date::Error => error
    redirect_to group_assignment_path(date: params[:date]), alert: error.message
  end

  def ignore_suggestion
    date = params[:date].present? ? Date.iso8601(params[:date]) : Date.current
    @schedule.with_lock do
      person = TimeOff::GroupRoster.new(schedule: @schedule, date: date).unassigned
        .find { |item| TimeOff::GroupRoster.key(item) == params[:person] }
      raise TimeOff::UpdateDay::InvalidChange, 'Selecione uma sugestão de colaborador DU sem grupo.' unless person

      key = TimeOff::GroupRoster.key(person)
      keys = @schedule.ignored_group_suggestions
      @schedule.update!(ignored_group_suggestions: (keys + [key]).uniq)
    end
    redirect_to time_off_schedule_path(suggestion_navigation), notice: 'Sugestão ignorada.'
  rescue ActiveRecord::RecordInvalid, TimeOff::UpdateDay::InvalidChange, Date::Error => error
    redirect_to time_off_schedule_path(suggestion_navigation), alert: error.message
  end

  def update_day
    attributes = params.require(:change).permit(:membership_id, :date, :status, :reason, :expected_revision)
    date = Date.iso8601(attributes[:date].to_s)
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: attributes[:membership_id], date: date,
      status: attributes[:status], reason: attributes[:reason], expected_revision: attributes[:expected_revision], user: current_user)
    respond_to do |format|
      format.json { render json: { message: 'Alteração salva.' } }
      format.html { redirect_to time_off_schedule_path(tab: 'day', date: date), notice: 'Alteração salva.' }
    end
  rescue TimeOff::UpdateDay::Conflict => error
    render_error(error.message, :conflict)
  rescue ActiveRecord::RecordInvalid, TimeOff::UpdateDay::InvalidChange, Date::Error => error
    render_error(error.message, :unprocessable_entity)
  end

  def revise_membership
    attributes = params.require(:membership).permit(:id, :starts_on, :group_code, :fixed_weekday, :standard_operation, :reason, :expected_updated_at)
    member = TimeOff::ReviseMembership.call(schedule: @schedule, membership_id: attributes[:id],
      starts_on: Date.iso8601(attributes[:starts_on].to_s), group_code: attributes[:group_code],
      fixed_weekday: attributes[:fixed_weekday].presence&.to_i, standard_operation: attributes[:standard_operation],
      reason: attributes[:reason], expected_updated_at: attributes[:expected_updated_at], user: current_user)
    redirect_to settings_path(correction: 1, membership_id: member.id), notice: 'Vigência corrigida. A correção foi registrada no histórico.'
  rescue ActiveRecord::RecordInvalid, TimeOff::UpdateDay::InvalidChange, TimeOff::UpdateDay::Conflict, Date::Error => error
    redirect_to settings_path(correction: 1, membership_id: attributes[:id]), alert: error.message
  end

  def delete_membership
    attributes = params.require(:membership).permit(:id, :reason, :expected_updated_at)
    TimeOff::DeleteMembership.call(schedule: @schedule, membership_id: attributes[:id],
      reason: attributes[:reason], expected_updated_at: attributes[:expected_updated_at], user: current_user)
    redirect_to settings_path(correction: 1), notice: 'Vigência excluída da escala. O histórico e as férias foram preservados.'
  rescue ActiveRecord::RecordInvalid, TimeOff::UpdateDay::InvalidChange, TimeOff::UpdateDay::Conflict => error
    redirect_to settings_path(correction: 1, membership_id: attributes[:id]), alert: error.message
  end

  def update_rotation
    @schedule.with_lock { @schedule.update!(recurring: params.require(:schedule).permit(:recurring)[:recurring]) }
    redirect_to time_off_schedule_path(tab: 'calendar', date: params[:date], settings: 1), notice: @schedule.recurring? ? 'Rodízio de 6 semanas habilitado após outubro.' : 'Piloto limitado a outubro de 2026.'
  end

  def create_vacation
    attributes = params.require(:vacation).permit(:membership_id, :starts_on, :ends_on, :reason)
    TimeOff::UpdateVacation.create(schedule: @schedule, membership_id: attributes[:membership_id],
      starts_on: Date.iso8601(attributes[:starts_on].to_s), ends_on: Date.iso8601(attributes[:ends_on].to_s), reason: attributes[:reason], user: current_user)
    redirect_to settings_path, notice: 'Férias cadastradas. O colaborador ficará indisponível durante o período.'
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, TimeOff::UpdateDay::InvalidChange, Date::Error => error
    redirect_to settings_path, alert: error.message
  end

  def cancel_vacation
    attributes = params.require(:vacation).permit(:id, :reason)
    TimeOff::UpdateVacation.cancel(schedule: @schedule, id: attributes[:id], reason: attributes[:reason], user: current_user)
    redirect_to settings_path, notice: 'Férias canceladas. A escala anterior voltou a valer.'
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, TimeOff::UpdateDay::InvalidChange => error
    redirect_to settings_path, alert: error.message
  end

  def update_coverage
    render json: { error: 'A composição de equipes foi movida para o PCD. Abra o módulo DU → PCD.' }, status: :gone
  end

  def preview_routing
    render json: { error: 'Importe a roteirização no módulo DU → PCD.' }, status: :gone
  end

  private

  def suggestion_navigation
    params.slice(:tab, :date, :month, :role, :group, :calendar_period, :page, :name, :per_page)
      .permit(:tab, :date, :month, :role, :group, :calendar_period, :page, :name, :per_page).to_h
  end
  helper_method :suggestion_navigation

  def group_assignment_path(date:)
    if params[:origin] == 'unassigned'
      context = params.permit(:tab, :role, :group, :month, :calendar_period, :page, :name, :per_page).to_h
      time_off_schedule_path(context.merge(date: params[:date].presence || date))
    else
      time_off_schedule_path(tab: 'calendar', date: date, settings: 1)
    end
  end

  def set_schedule
    @schedule = TimeOffSchedule.order(:id).first!
  end

  def time_off_tab_path(tab, **options)
    context = params.slice(:calendar_period, :page, :name, :per_page).permit(:calendar_period, :page, :name, :per_page).to_h.symbolize_keys
    time_off_schedule_path(context.merge(tab: tab, date: @date, role: @role, group: @group).merge(options))
  end
  helper_method :time_off_tab_path

  def prepare_calendar_days
    @periods = @month.step(@month.end_of_month, 7).map { |start| start..[start + 6, @month.end_of_month].min }
    if params[:calendar_period] == 'month'
      @calendar_period = 'month'
    else
      requested_day = params[:calendar_period].present? ? Date.iso8601(params[:calendar_period]) : @month
      period = @periods.find { |range| range.cover?(requested_day) } || @periods.first
      @calendar_period = period.first.iso8601
      @days = period.to_a
    end
  end

  def paginate_calendar
    @total_rows = @visible_memberships.size
    @total_pages = [(@total_rows.to_f / @per_page).ceil, 1].max
    @page = [[params[:page].to_i, 1].max, @total_pages].min
    @calendar_memberships = @visible_memberships.slice((@page - 1) * @per_page, @per_page) || []
  end

  def normalize_name(name)
    I18n.transliterate(name.to_s).downcase.squish
  end

  def calendar_path(**options)
    time_off_tab_path('calendar', month: @month.strftime('%Y-%m'), calendar_period: @calendar_period, page: @page, **options)
  end
  helper_method :calendar_path

  def calendar_month_path(direction)
    month = @month + direction.months
    calendar_path(date: month, month: month.strftime('%Y-%m'), calendar_period: @calendar_period == 'month' ? 'month' : month.iso8601, page: 1)
  end
  helper_method :calendar_month_path

  def status_for(member, date)
    @availability.status(member, date)
  end
  helper_method :status_for

  def day_member_visible?(member)
    member && (!@role || member.role(@date) == @role) && (!@group || member.group_code == @group)
  end

  def day_car_visible?(car)
    return false unless car['scheduled']
    members = TimeOff::Board::ROLES.filter_map { |role| @coverage.member(car[role]) }
    members.empty? || members.any? { |member| day_member_visible?(member) }
  end
  helper_method :day_member_visible?, :day_car_visible?

  def settings_path(**options)
    context = params.slice(:role, :group, :month, :calendar_period, :page, :name, :per_page).permit(:role, :group, :month, :calendar_period, :page, :name, :per_page).to_h
    time_off_schedule_path(context.merge(tab: %w[calendar day extras history].include?(params[:tab]) ? params[:tab] : 'calendar', date: params[:date], settings: 1).merge(options))
  end

  def can_edit?
    current_user&.can_manage_time_off?
  end
  helper_method :can_edit?

  def require_access!
    head :forbidden unless current_user.can_view_du_operations?
  end

  def require_editor!
    head :forbidden unless can_edit?
  end

  def render_error(message, status)
    respond_to do |format|
      format.json { render json: { error: message }, status: status }
      format.html { redirect_to time_off_schedule_path(tab: 'day', date: params.dig(:change, :date)), alert: message }
    end
  end
end
