class MeetingMinutesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_action_plan
  before_action :set_meeting, only: [:show, :create_tasks]
  before_action :ensure_meeting_access!, only: [:show, :create_tasks]

  def new
    @meeting = @action_plan.meeting_minutes.new(
      meeting_date: Date.current,
      title: "Reunião - #{@action_plan.name}"
    )
  end

  def create
    @meeting = @action_plan.meeting_minutes.new(meeting_params)
    @meeting.creator = current_user
    @meeting.status = :queued

    if @meeting.save
      MeetingMinuteGenerationJob.perform_later(@meeting.id)
      redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
        notice: "A gravação foi recebida. A ata será gerada em segundo plano."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @buckets = @action_plan.buckets.order(:position)
    @users = User.order(:name)
  end

  def create_tasks
    suggestion_ids = Array(params[:suggestion_ids]).map(&:to_i)
    suggestions = Array(@meeting.tasks_suggestions)

    created_count = 0

    ActiveRecord::Base.transaction do
      suggestion_ids.each do |index|
        suggestion = suggestions[index]
        next unless suggestion.present?

        bucket = @action_plan.buckets.find(params.dig(:bucket_ids, index.to_s))
        task = bucket.tasks.create!(
          title: suggestion["title"].presence || "Tarefa da reunião",
          description: suggestion["description"],
          start_at: Time.current,
          due_at: parse_due_date(suggestion["due_date"]),
          creator: current_user,
          user_ids: valid_user_ids(params.dig(:assignee_ids, index.to_s))
        )
        created_count += 1 if task.persisted?
      end
    end

    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
      notice: "#{created_count} tarefa(s) criada(s) a partir da ata."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to action_plan_meeting_minute_path(@action_plan, @meeting),
      alert: "Não foi possível criar as tarefas: #{e.message}"
  end

  private

  def parse_due_date(value)
    Date.parse(value).end_of_day if value.present?
  rescue ArgumentError
    nil
  end

  def valid_user_ids(value)
    Array(value).reject(&:blank?).map(&:to_i).then { |ids| User.where(id: ids).pluck(:id) }
  end

  def set_action_plan
    @action_plan = accessible_action_plans.find(params[:action_plan_id])
  end

  def set_meeting
    @meeting = @action_plan.meeting_minutes.find(params[:id])
  end

  def ensure_meeting_access!
    return if current_user.admin? || @meeting.creator_id == current_user.id || @action_plan.user_id == current_user.id

    redirect_to action_plans_path, alert: "Você não possui acesso a esta ata."
  end

  def accessible_action_plans
    return ActionPlan.all if current_user.admin?

    ActionPlan
      .left_joins(buckets: { tasks: :task_assignments })
      .where(
        "action_plans.user_id = :user_id
         OR tasks.creator_id = :user_id
         OR task_assignments.user_id = :user_id",
        user_id: current_user.id
      )
      .distinct
  end

  def meeting_params
    params.require(:meeting_minute).permit(:title, :meeting_date, :audio)
  end
end
