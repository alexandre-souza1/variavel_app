class ChecklistOccurrencesController < ApplicationController
  include TaskAccess
  FILTER_KEYS = %i[year employee_id employee_sector month day display status subject spot_plate page active_only].freeze
  before_action :authenticate_user!
  before_action :require_tracking_access!
  before_action :set_task, only: %i[create cancel]

  def index
    prepare_report_filters(directory: true)
    prepare_dashboard
    prepare_candidates if @display == "review"
  end

  def details
    prepare_report_filters
    prepare_modal
    render partial: "checklist_occurrences/occurrence_modal"
  end

  def exclude
    occurrence = ChecklistOccurrence.from_tracking_sources.visible_to(current_user).find(params[:id])
    raise ActiveRecord::RecordNotFound unless occurrence.spot? || tracking_employees.exists?(occurrence.employee_id)
    attributes = params.require(:exclusion).permit(:reason, :details)
    ChecklistTracking::Exclusion.new(occurrence: occurrence, user: current_user,
      reason: attributes[:reason], details: attributes[:details]).call
    result = { message: "Ocorrência desconsiderada. A justificativa foi preservada no histórico." }
    if params[:dashboard].present? && params[:modal].present?
      prepare_report_filters(params.require(:dashboard).permit(*FILTER_KEYS))
      prepare_dashboard
      result[:fragments] = dashboard_fragments
      prepare_report_filters(params.require(:modal).permit(*FILTER_KEYS))
      prepare_modal
      result[:modal] = render_to_string(partial: "checklist_occurrences/occurrence_modal_content", formats: [:html])
    end
    render json: result
  rescue ChecklistTracking::Exclusion::InvalidChange => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def identify
    tasks = Task.accessible_to(current_user)
    result = ChecklistTracking::AutomaticRegistration.new(user: current_user, tasks: tasks, year: selected_year, employee_sector: selected_employee_sector, subject: selected_subject).call
    redirect_to checklist_occurrences_path(year: selected_year, employee_sector: selected_employee_sector, display: params[:display] == "review" ? "review" : nil, subject: selected_subject == "spot" ? "spot" : nil), status: :see_other,
      notice: "#{helpers.pluralize(result.created, 'ação vinculada', 'ações vinculadas')} automaticamente. #{helpers.pluralize(result.pending, 'ação para conferência', 'ações para conferência')}. Registros anteriores e correções foram preservados."
  end

  def create
    attributes = params.require(:checklist_occurrence).permit(:employee_id, :spot_plate, :occurred_on, :checklist_kind, :notes)
    employee_id = attributes.delete(:employee_id)
    employee = tracking_employees.find(employee_id) if employee_id.present?
    @task.with_lock do
      occurrence = @task.checklist_occurrences.create!(attributes.merge(employee: employee, recorded_by: current_user))
      log_occurrence(occurrence, "registered")
    end
    tracking_response("Ocorrência registrada.")
  rescue ActiveRecord::RecordInvalid => error
    tracking_response(error.record.errors.full_messages.to_sentence, status: :unprocessable_entity)
  rescue ActiveRecord::RecordNotUnique
    tracking_response("Esta ocorrência já está registrada nesta tarefa.", status: :unprocessable_entity)
  end

  def cancel
    occurrence = ChecklistOccurrence.visible_to(current_user).where(task: @task).find(params[:id])
    @task.with_lock do
      occurrence.reload
      unless occurrence.cancelled_at?
        occurrence.update!(cancelled_at: Time.current, cancelled_by: current_user,
          cancellation_reason: params[:cancellation_reason].to_s.strip)
        log_occurrence(occurrence, "cancelled")
      end
    end
    tracking_response("Ocorrência desconsiderada. O registro foi mantido no histórico.")
  rescue ActiveRecord::RecordInvalid => error
    tracking_response(error.record.errors.full_messages.to_sentence, status: :unprocessable_entity)
  end

  private

  def prepare_report_filters(filters = params, directory: false)
    @spot_mode = selected_subject(filters) == "spot"
    @year = selected_year(filters)
    @employee_sector = selected_employee_sector(filters)
    raise ActiveRecord::RecordNotFound if @employee_sector && !current_user.employee_sectors.include?(@employee_sector)
    @display = filters[:display].in?(%w[annual calendar history review]) ? filters[:display] : "annual"
    @active_only = !@spot_mode && (%w[annual calendar].include?(@display) || filters[:active_only] == "1")
    employees = tracking_employees(sector: @employee_sector)
    employees = employees.active if @active_only
    @employees = nil
    @employee = nil
    if !@spot_mode && filters[:employee_id].present?
      selected_employee = Employee.for_checklist_tracking(current_user).find(filters[:employee_id])
      @employee = selected_employee if employees.exists?(selected_employee.id)
    end
    @employees = employees.order(:nome).to_a if directory && !@spot_mode

    visible = ChecklistOccurrence.from_tracking_sources.visible_to(current_user)
    @occurrence_scope = @spot_mode ? visible.spots : visible.employees.where(employee_id: employees.select(:id))
    @spot_plates = @spot_mode && directory ? @occurrence_scope.distinct.order(:spot_plate).pluck(:spot_plate) : []
    @spot_plate = @spot_mode ? ChecklistOccurrence.normalize_spot_plate(filters[:spot_plate]).presence : nil
    @month = filters[:month].to_i.between?(1, 12) ? filters[:month].to_i : nil
    @month ||= Date.current.month if @display == "calendar"
    @day = Date.iso8601(filters[:day].to_s) rescue nil
    @day = nil if @day && (@day.year != @year || (@month && @day.month != @month))
    @calendar_date = Date.new(@year, @month || Date.current.month, 1)
    @tracking_filters = { year: @year, employee_id: @employee&.id, month: @month,
      employee_sector: @employee_sector, display: @display, day: @day&.iso8601,
      subject: @spot_mode ? "spot" : nil, spot_plate: @spot_plate, active_only: @active_only ? "1" : nil }.compact
    @requested_page = filters[:page].to_i
    @excluded_only = filters[:status] == "excluded"
  end

  def prepare_dashboard
    roster = @employees || tracking_employees(sector: @employee_sector).active.order(:nome).to_a if @active_only
    @report = ChecklistTracking::Report.new(scope: @occurrence_scope, year: @year, employees: roster)
    if @display == "calendar"
      @calendar_events = @report.events.select { |event| selected_subject_event?(event) }.group_by { |event| event[:date] }
    elsif @display == "history"
      @excluded_count = ChecklistTracking::History.new(scope: history_scope).excluded_count
      @events = @report.events.select do |event|
        selected_subject_event?(event) && (!@month || event[:date].month == @month) && (!@day || event[:date] == @day)
      end
      @event_count = @events.size
      @page = @requested_page.clamp(1, [(@event_count / 20.0).ceil, 1].max)
      @events = @events.slice((@page - 1) * 20, 20) || []
      records = @events.flat_map { |event| event[:sources] }
      @accessible_history_task_ids = Task.accessible_to(current_user).where(id: records.map(&:task_id)).pluck(:id).to_set
      ActiveRecord::Associations::Preloader.new(records: records, associations: [:recorded_by,
        { task: [:labels, { bucket: :action_plan }, { routine_value: :routine }] }]).call
    end
  end

  def prepare_modal
    @history_events = ChecklistTracking::History.new(scope: history_scope).events
    @history_events = @history_events.select { |event| event[:excluded] } if @excluded_only
    task_ids = @history_events.flat_map { |event| event[:sources].map(&:task_id) }
    @accessible_history_task_ids = Task.accessible_to(current_user).where(id: task_ids).pluck(:id).to_set
  end

  def dashboard_fragments
    fragments = { "tracking-summary" => render_to_string(partial: "checklist_occurrences/summary", formats: [:html]) }
    partial = @display == "history" ? "history" : "overview" unless @display == "review"
    if partial
      id = @display == "history" ? "tracking-history" : "tracking-overview"
      fragments[id] = render_to_string(partial: "checklist_occurrences/#{partial}", formats: [:html],
        locals: { filters: @tracking_filters, months: I18n.t("date.abbr_month_names")[1..12] })
    end
    fragments
  end

  def prepare_candidates
    @all_tracking_employees = Employee.for_checklist_tracking(current_user).includes(:employee_names, :employee_roles).order(:nome).to_a
    @employees ||= []
    @name_matcher = ChecklistTracking::NameMatcher.new(@all_tracking_employees)
    employee_ids = @employees.map(&:id).to_set
    @employees = @all_tracking_employees.select { |employee| employee_ids.include?(employee.id) }
    tasks = Task.accessible_to(current_user)
    @candidates = ChecklistTracking::TaskSource.candidates(tasks)
      .where.not(id: ChecklistOccurrence.select(:task_id))
      .includes(:labels, :comments, :routine_comment, :checklist_occurrences, bucket: :action_plan, routine_value: :routine_indicator)
      .order(created_at: :desc).map { |task| ChecklistTracking::TaskSource.new(task) }
      .select do |source|
        next false unless source.spot? == @spot_mode && source.suggested_date.year == @year
        next true unless @employee_sector
        person = source.name_match(@all_tracking_employees, matcher: @name_matcher).employee
        !person || employee_ids.include?(person.id)
      end
    @candidate_count = @candidates.size
    @ready_count = @candidates.count { |source| source.automatic_attributes(@all_tracking_employees, matcher: @name_matcher) }
    @candidate_page = params[:candidate_page].to_i.clamp(1, [(@candidate_count / 15.0).ceil, 1].max)
    @candidates = @candidates.slice((@candidate_page - 1) * 15, 15) || []
  end

  def history_scope
    scope = @occurrence_scope.where(occurred_on: Date.new(@year, 1, 1)..Date.new(@year, 12, 31))
    scope = scope.where(employee_id: @employee.id) if @employee
    scope = scope.where(spot_plate: @spot_plate) if @spot_plate
    scope = scope.where(occurred_on: @calendar_date..@calendar_date.end_of_month) if @month
    scope = scope.where(occurred_on: @day) if @day
    scope
  end

  def selected_subject(filters = params)
    filters[:subject] == "spot" ? "spot" : "employees"
  end

  def selected_subject_event?(event)
    (!@employee || event[:employee] == @employee) && (!@spot_plate || event[:spot_plate] == @spot_plate)
  end

  def selected_employee_sector(filters = params)
    return if selected_subject(filters) == "spot"
    filters[:employee_sector].presence || (current_user.employee_sectors.one? ? current_user.employee_sectors.first : nil)
  end

  def tracking_employees(sector: selected_employee_sector)
    scope = Employee.for_checklist_tracking(current_user)
    sector ? scope.in_current_or_last_sector(sector) : scope
  end

  def selected_year(filters = params)
    filters[:year].to_s.match?(/\A\d{4}\z/) && filters[:year].to_i.between?(1900, 9999) ? filters[:year].to_i : Date.current.year
  end

  def require_tracking_access!
    return head :forbidden unless current_user.can_view_checklist_tracking?
    head :forbidden if selected_employee_sector && !current_user.employee_sectors.include?(selected_employee_sector)
  end

  def set_task
    @task = find_accessible_task(params[:task_id])
    head :forbidden if @task.inbox?
  end

  def log_occurrence(occurrence, action)
    TaskActivityService.log(task: @task, user: current_user, activity_type: :updated,
      new_value: "#{occurrence.subject_name} · #{I18n.l(occurrence.occurred_on)} · #{occurrence.kind_label}",
      metadata: { field: "checklist_occurrence", action: action, occurrence_id: occurrence.id,
                  reason: occurrence.cancellation_reason })
  end

  def tracking_response(message, status: :ok)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("task-checklist-occurrences-#{@task.id}",
          partial: "checklist_occurrences/task_panel", locals: { task: @task.reload, message: message,
            error: status == :unprocessable_entity }), status: :ok
      end
      format.html do
        redirect_to checklist_occurrences_path(year: params[:year].presence || Date.current.year, employee_sector: selected_employee_sector, display: params[:display] == "review" ? "review" : nil, subject: selected_subject == "spot" ? "spot" : nil),
          status: :see_other, **{ status == :unprocessable_entity ? :alert : :notice => message }
      end
    end
  end
end
