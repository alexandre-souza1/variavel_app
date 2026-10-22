class ChecklistOccurrencesController < ApplicationController
  include TaskAccess
  before_action :authenticate_user!
  before_action :require_tracking_access!
  before_action :set_task, only: %i[create cancel]

  def index
    prepare_report_filters
    @report = ChecklistTracking::Report.new(scope: @occurrence_scope, year: @year)
    @calendar_events = @report.events.select { |event| !@employee || event[:employee] == @employee }.group_by { |event| event[:date] }
    @excluded_count = history_scope.group(:employee_id, :occurred_on, :checklist_kind)
      .having("COUNT(*) FILTER (WHERE cancelled_at IS NULL) = 0").count.size
    @events = @report.events.select do |event|
      (!@employee || event[:employee] == @employee) && (!@month || event[:date].month == @month) && (!@day || event[:date] == @day)
    end
    @event_count = @events.size
    @page = params[:page].to_i.clamp(1, [(@event_count / 20.0).ceil, 1].max)
    @events = @events.slice((@page - 1) * 20, 20) || []
    history_task_ids = @events.flat_map { |event| event[:sources].map(&:task_id) }
    @accessible_history_task_ids = Task.accessible_to(current_user).where(id: history_task_ids).pluck(:id).to_set

    tasks = Task.accessible_to(current_user)
    tasks = tasks.where(bucket_id: @plan.bucket_ids) if @plan
    @candidates = ChecklistTracking::TaskSource.candidates(tasks)
      .where.not(id: ChecklistOccurrence.select(:task_id))
      .includes(:comments, :routine_comment, :checklist_occurrences, bucket: :action_plan, routine_value: :routine_indicator)
      .order(created_at: :desc).map { |task| ChecklistTracking::TaskSource.new(task) }
      .select do |source|
        person = source.name_match(@all_tracking_employees, matcher: @name_matcher).employee
        source.suggested_date.year == @year && (!@employee_sector || !person || @employees.any? { |employee| employee.id == person.id })
      end
    @candidate_count = @candidates.size
    @ready_count = @candidates.count { |source| source.automatic_attributes(@all_tracking_employees, matcher: @name_matcher) && !source.task.checklist_occurrences.any? }
    @candidate_page = params[:candidate_page].to_i.clamp(1, [(@candidate_count / 15.0).ceil, 1].max)
    @candidates = @candidates.slice((@candidate_page - 1) * 15, 15) || []
  end

  def details
    prepare_report_filters
    @history_events = ChecklistTracking::History.new(scope: history_scope).events
    @history_events = @history_events.select { |event| event[:excluded] } if params[:status] == "excluded"
    task_ids = @history_events.flat_map { |event| event[:sources].map(&:task_id) }
    @accessible_history_task_ids = Task.accessible_to(current_user).where(id: task_ids).pluck(:id).to_set
    @modal_filters = params.permit(:year, :action_plan_id, :employee_id, :employee_sector, :month, :day, :display, :status).to_h
    render partial: "checklist_occurrences/occurrence_modal"
  end

  def exclude
    occurrence = ChecklistOccurrence.visible_to(current_user).where(employee_id: tracking_employees.select(:id)).find(params[:id])
    attributes = params.require(:exclusion).permit(:reason, :details)
    ChecklistTracking::Exclusion.new(occurrence: occurrence, user: current_user,
      reason: attributes[:reason], details: attributes[:details]).call
    render json: { message: "Ocorrência desconsiderada. A justificativa foi preservada no histórico." }
  rescue ChecklistTracking::Exclusion::InvalidChange => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def identify
    plan = ActionPlan.visible_to(current_user).find(params[:action_plan_id]) if params[:action_plan_id].present?
    tasks = Task.accessible_to(current_user)
    tasks = tasks.where(bucket_id: plan.bucket_ids) if plan
    result = ChecklistTracking::AutomaticRegistration.new(user: current_user, tasks: tasks, year: selected_year, employee_sector: selected_employee_sector).call
    redirect_to checklist_occurrences_path(action_plan_id: plan&.id, year: selected_year, employee_sector: selected_employee_sector, display: params[:display] == "review" ? "review" : nil), status: :see_other,
      notice: "#{helpers.pluralize(result.created, 'ação vinculada', 'ações vinculadas')} automaticamente. #{helpers.pluralize(result.pending, 'ação para conferência', 'ações para conferência')}. Registros anteriores e correções foram preservados."
  end

  def create
    attributes = params.require(:checklist_occurrence).permit(:employee_id, :occurred_on, :checklist_kind, :notes)
    employee = tracking_employees.find(attributes.delete(:employee_id))
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

  def prepare_report_filters
    @plans = ActionPlan.visible_to(current_user).order(:name)
    @plan = @plans.find(params[:action_plan_id]) if params[:action_plan_id].present?
    @year = selected_year
    @employee_sector = selected_employee_sector
    @all_tracking_employees = Employee.for_checklist_tracking(current_user).includes(:employee_names).order(:nome).to_a
    @employees = tracking_employees.includes(:employee_names).order(:nome).to_a
    @name_matcher = ChecklistTracking::NameMatcher.new(@all_tracking_employees)
    @employee = @employees.find { |employee| employee.id.to_s == params[:employee_id] }
    raise ActiveRecord::RecordNotFound if params[:employee_id].present? && !@employee && !@all_tracking_employees.any? { |employee| employee.id.to_s == params[:employee_id] }

    @occurrence_scope = ChecklistOccurrence.visible_to(current_user).where(employee_id: @employees.map(&:id))
    @occurrence_scope = @occurrence_scope.where(task_id: @plan.buckets.joins(:tasks).select("tasks.id")) if @plan
    @display = params[:display].in?(%w[annual calendar history review]) ? params[:display] : "annual"
    @month = params[:month].to_i if params[:month].to_i.between?(1, 12)
    @month ||= Date.current.month if @display == "calendar"
    @day = Date.iso8601(params[:day].to_s) rescue nil
    @day = nil if @day && (@day.year != @year || (@month && @day.month != @month))
    @calendar_date = Date.new(@year, @month || Date.current.month, 1)
  end

  def history_scope
    scope = @occurrence_scope.where(occurred_on: Date.new(@year, 1, 1)..Date.new(@year, 12, 31))
    scope = scope.where(employee_id: @employee.id) if @employee
    scope = scope.where(occurred_on: @calendar_date..@calendar_date.end_of_month) if @month
    scope = scope.where(occurred_on: @day) if @day
    scope
  end

  def selected_employee_sector
    params[:employee_sector].presence || (current_user.employee_sectors.one? ? current_user.employee_sectors.first : nil)
  end

  def tracking_employees
    scope = Employee.for_checklist_tracking(current_user)
    selected_employee_sector ? scope.in_current_or_last_sector(selected_employee_sector) : scope
  end

  def selected_year
    params[:year].to_s.match?(/\A\d{4}\z/) && params[:year].to_i.between?(1900, 9999) ? params[:year].to_i : Date.current.year
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
      new_value: "#{occurrence.employee.nome} · #{I18n.l(occurrence.occurred_on)} · #{occurrence.kind_label}",
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
        redirect_to checklist_occurrences_path(action_plan_id: params[:tracking_dashboard] == "1" ? params[:tracking_plan_id].presence : @task.bucket.action_plan_id,
          year: params[:year].presence || Date.current.year, employee_sector: selected_employee_sector, display: params[:display] == "review" ? "review" : nil),
          status: :see_other, **{ status == :unprocessable_entity ? :alert : :notice => message }
      end
    end
  end
end
