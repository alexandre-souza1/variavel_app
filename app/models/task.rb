class Task < ApplicationRecord
  belongs_to :bucket
  belongs_to :creator, class_name: "User"
  acts_as_list scope: :bucket
  has_many :comments, dependent: :destroy
  has_one :tasklist, dependent: :destroy
  accepts_nested_attributes_for :tasklist, allow_destroy: true
  has_many :task_assignments, dependent: :destroy
  has_many :users, through: :task_assignments
  has_many :task_labels, dependent: :destroy
  has_many :labels, through: :task_labels
  include ActionView::RecordIdentifier

  after_initialize do
    self.completed = false if self.completed.nil?
    self.start_at ||= Time.current
  end

  after_update_commit :create_next_task_if_completed
  after_create :ensure_tasklist


  def create_next_task_if_completed
    return unless saved_change_to_completed? && completed?
    return if recurrence.blank? || due_at.blank?

    next_date = case recurrence
                when "daily"   then due_at + 1.day
                when "weekly"  then due_at + 1.week
                when "monthly" then due_at + 1.month
                end

    return if Task.exists?(bucket: bucket, due_at: next_date, title: title)

    new_task = Task.new(
      title: title,
      description: description,
      bucket: bucket,
      start_at: start_at,
      due_at: next_date,
      recurrence: recurrence,
      creator: creator,
      user_ids: user_ids,      # ← usa os IDs
      label_ids: label_ids     # ← se tiver labels, também use IDs
    )

    if new_task.save
      broadcast_new_task(new_task)
    else
      Rails.logger.error "❌ Falha ao criar tarefa recorrente: #{new_task.errors.full_messages}"
    end
  end

  after_update_commit :broadcast_task_update

  def broadcast_task_update
    action_plan = bucket.action_plan
    bucket_id = bucket.id

    Turbo::StreamsChannel.broadcast_remove_to(
      "tasks_action_plan_#{action_plan.id}",
      target: dom_id(self)
    )

    target_list = completed? ? "done-tasks-#{bucket_id}" : "open-tasks-#{bucket_id}"

    Turbo::StreamsChannel.broadcast_prepend_to(
      "tasks_action_plan_#{action_plan.id}",
      target: target_list,
      partial: "tasks/task",
      locals: { task: self }
    )
    Turbo::StreamsChannel.broadcast_update_to(
      "tasks_action_plan_#{action_plan.id}",
      target: "done-count-#{bucket_id}",
      html: "✔️ Tarefas concluídas (#{bucket.done_count})"
    )
  end

  def ensure_tasklist
    create_tasklist(title: "Checklist") unless tasklist.present?
  end

  def broadcast_new_task(task)
    action_plan = task.bucket.action_plan

    Turbo::StreamsChannel.broadcast_prepend_to(
      "tasks_action_plan_#{action_plan.id}",
      target: "open-tasks-#{task.bucket.id}",
      partial: "tasks/task",
      locals: { task: task }
    )
  end
end
