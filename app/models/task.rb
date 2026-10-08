class Task < ApplicationRecord
  attr_accessor :inbox_assignee_ids_before_move, :broadcast_as_move
  belongs_to :bucket
  belongs_to :creator, class_name: "User"
  validates :title, presence: true
  belongs_to :routine_value, optional: true
  validate :routine_source_matches_plan
  validate :inbox_belongs_to_creator
  validate :bucket_transition_allowed
  validate :labels_match_plan
  before_save :discard_labels_from_previous_plan, if: :will_save_change_to_bucket_id?
  acts_as_list scope: :bucket
  has_many :comments, dependent: :destroy
  has_one :tasklist, dependent: :destroy
  accepts_nested_attributes_for :tasklist, allow_destroy: true
  has_many :task_assignments, dependent: :destroy
  has_many :users, through: :task_assignments
  has_many :task_labels, dependent: :destroy
  has_many :labels, through: :task_labels
  has_many :task_activities, dependent: :destroy
  include ActionView::RecordIdentifier

  scope :visible_for, ->(user) do
    scope = joins(:bucket).where(buckets: { inbox: false })
      .or(joins(:bucket).where(creator_id: user.id, buckets: { inbox: true, user_id: user.id }))
    if user.mechanical?
      scope.where(id: TaskAssignment.where(user_id: user.id).select(:task_id))
        .or(scope.where(creator_id: user.id, buckets: { inbox: true }))
    else
      scope
    end
  end

  scope :accessible_to, ->(user) do
    joins(:bucket).where(buckets: { action_plan_id: ActionPlan.visible_to(user).select(:id) })
      .or(joins(:bucket).where(creator_id: user.id, buckets: { inbox: true, user_id: user.id }))
      .visible_for(user)
  end

  def inbox?
    bucket&.inbox?
  end

  def feed_stream
    "task_feed_#{id}_bucket_#{bucket_id}"
  end

  def task_list_id
    "#{completed? && !inbox? ? 'done' : 'open'}-tasks-#{bucket_id}"
  end

  def move_stream_attributes
    tasks = bucket.tasks.where("position < ?", position)
    tasks = tasks.where(completed: completed?) unless inbox?
    preceding_ids = tasks.order(:position).pluck(:id).map { |id| "task_#{id}" }
    { "task-id" => dom_id(self), "position" => preceding_ids.size,
      "preceding-task-ids" => preceding_ids.to_json, "version" => updated_at.iso8601(6) }
  end

  after_initialize do
    self.completed = false if self.completed.nil?
    self.start_at ||= Time.current
  end

  before_save :reset_due_notification_sent_at, if: :should_reset_due_notification?
  after_update_commit :create_next_task_if_completed
  after_create :ensure_tasklist
  after_create_commit :broadcast_generated_task, if: :routine_value_id?
  after_create_commit :broadcast_inbox_task, if: :inbox?
  after_commit :notify_due_soon_if_needed, on: %i[create update]


  def create_next_task_if_completed
    return unless saved_change_to_completed? && completed?
    return if recurrence.blank? || due_at.blank?

    next_date = case recurrence
                when "daily"   then due_at + 1.day
                when "weekly"  then due_at + 1.week
                when "monthly" then due_at + 1.month
                when "bimonthly" then due_at + 2.months
                end

    return if Task.exists?(bucket: bucket, due_at: next_date, title: title)

    new_task = Task.new(
      title: title,
      description: description,
      bucket: bucket,
      start_at: Time.current,
      due_at: next_date,
      recurrence: recurrence,
      clone_tasklist_on_recurrence: clone_tasklist_on_recurrence,
      due_notification_enabled: due_notification_enabled,
      creator: creator,
      user_ids: user_ids,      # ← usa os IDs
      label_ids: label_ids || []
    )

    if new_task.save
      clone_tasklist_to(new_task) if clone_tasklist_on_recurrence?
      broadcast_new_task(new_task)
    else
      Rails.logger.error "❌ Falha ao criar tarefa recorrente: #{new_task.errors.full_messages}"
    end
  end

  after_update_commit :broadcast_task_update
  after_update_commit :notify_assignees_when_planned

  def notify_assignees_when_planned
    return unless saved_change_to_bucket_id? && !inbox?
    return unless Bucket.find_by(id: bucket_id_before_last_save)&.inbox?

    recipients = inbox_assignee_ids_before_move.nil? ? users : users.where(id: inbox_assignee_ids_before_move)
    recipients.each { |user| NotificationDelivery.task_assigned(task: self, user: user, actor: creator) }
  end

  def broadcast_task_update
    return broadcast_task_move if broadcast_as_move

    bucket_id = bucket.id
    stream = task_stream(bucket)

    if saved_change_to_bucket_id?
      previous_bucket = Bucket.find_by(id: bucket_id_before_last_save)
      if previous_bucket
        Turbo::StreamsChannel.broadcast_remove_to(task_stream(previous_bucket), target: dom_id(self))
        broadcast_inbox_count(previous_bucket) if previous_bucket.inbox?
        unless previous_bucket.inbox?
          Turbo::StreamsChannel.broadcast_update_to(task_stream(previous_bucket),
            target: "done-count-#{previous_bucket.id}", html: "✔️ Tarefas concluídas (#{previous_bucket.done_count})")
        end
      end
    end

    Turbo::StreamsChannel.broadcast_remove_to(
      stream,
      target: dom_id(self)
    )

    target_list = completed? && !inbox? ? "done-tasks-#{bucket_id}" : "open-tasks-#{bucket_id}"

    Turbo::StreamsChannel.broadcast_prepend_to(
      stream,
      target: target_list,
      partial: "tasks/task",
      locals: { task: self }
    )
    Turbo::StreamsChannel.broadcast_update_to(
      stream,
      target: "done-count-#{bucket_id}",
      html: "✔️ Tarefas concluídas (#{bucket.done_count})"
    )
    broadcast_gerot_task_update
    broadcast_inbox_count(bucket) if inbox?
  end

  def ensure_tasklist
    create_tasklist(title: "Checklist") unless tasklist.present?
  end

  def broadcast_new_task(task)
    Turbo::StreamsChannel.broadcast_prepend_to(
      task_stream(task.bucket),
      target: "open-tasks-#{task.bucket.id}",
      partial: "tasks/task",
      locals: { task: task }
    )
  end

  def start_time
    due_at&.to_date
  end


  def end_time
    due_at&.to_date
  end

  private

  def broadcast_task_move
    stream = task_stream(bucket)
    attributes = move_stream_attributes
    previous_bucket = Bucket.find_by(id: bucket_id_before_last_save) if saved_change_to_bucket_id?
    if previous_bucket && task_stream(previous_bucket) != stream
      # Only the destination receives the card content. A task returning to its
      # private inbox must not send its new content to the former plan's stream.
      Turbo::StreamsChannel.broadcast_action_to(task_stream(previous_bucket),
        action: :task_move, target: task_list_id,
        attributes: attributes.slice("task-id", "version"), render: false)
      broadcast_inbox_count(previous_bucket) if previous_bucket.inbox?
    end
    Turbo::StreamsChannel.broadcast_action_to(stream,
      action: :task_move, target: task_list_id, attributes: attributes,
      partial: "tasks/task", locals: { task: self })
    [previous_bucket, bucket].compact.uniq.each do |source_bucket|
      Turbo::StreamsChannel.broadcast_update_to(task_stream(source_bucket),
        target: "done-count-#{source_bucket.id}", html: "✔️ Tarefas concluídas (#{source_bucket.done_count})")
    end
    broadcast_inbox_count(bucket) if inbox?
    broadcast_gerot_task_update
  end

  def broadcast_inbox_task
    broadcast_new_task(self)
    broadcast_inbox_count(bucket)
  end

  def broadcast_inbox_count(inbox_bucket)
    stream = task_stream(inbox_bucket)
    count = inbox_bucket.tasks.count
    Turbo::StreamsChannel.broadcast_update_to(stream, target: "inbox-count-#{inbox_bucket.user_id}", html: "#{count} #{count == 1 ? 'tarefa' : 'tarefas'}")
    Turbo::StreamsChannel.broadcast_update_to(stream, target: "inbox-launcher-count-#{inbox_bucket.user_id}", html: count.to_s)
  end

  def task_stream(source_bucket)
    source_bucket.inbox? ? "tasks_inbox_#{source_bucket.user_id}" : "tasks_action_plan_#{source_bucket.action_plan_id}"
  end

  def inbox_belongs_to_creator
    return unless inbox? && bucket.user_id != creator_id

    errors.add(:bucket, "deve ser a Entrada do criador da tarefa")
  end

  def bucket_transition_allowed
    return unless persisted? && will_save_change_to_bucket_id?

    previous_bucket = Bucket.find_by(id: bucket_id_in_database)
    return if previous_bucket.nil? || previous_bucket.inbox? || inbox?
    return if previous_bucket.action_plan_id == bucket&.action_plan_id

    errors.add(:bucket, "deve pertencer ao mesmo plano de ação")
  end

  def discard_labels_from_previous_plan
    allowed_ids = bucket&.action_plan&.label_ids || []
    self.labels = labels.select { |label| allowed_ids.include?(label.id) }
  end

  def labels_match_plan
    # A valid move removes incompatible labels when saved, without changing
    # persisted associations during validation or a rejected move.
    return if will_save_change_to_bucket_id?
    return if labels.all? { |label| !inbox? && label.action_plan_id == bucket&.action_plan_id }

    errors.add(:labels, "devem pertencer ao plano da tarefa")
  end

  def routine_source_matches_plan
    return if routine_value.blank?
    return if !inbox? && routine_value.routine.action_plan_id == bucket&.action_plan_id

    errors.add(:bucket, "deve pertencer ao plano de ação do GEROT de origem")
  end

  def broadcast_generated_task
    broadcast_new_task(self)
    broadcast_gerot_task_update
  end

  def broadcast_gerot_task_update
    return if routine_value.blank?

    routine = routine_value.routine
    [bucket.action_plan, routine].each do |source|
      if broadcast_as_move
        Turbo::StreamsChannel.broadcast_action_to(source, :gerot_tasks,
          action: :task_move, target: task_list_id, attributes: move_stream_attributes,
          partial: "tasks/task", locals: { task: self })
      else
        Turbo::StreamsChannel.broadcast_remove_to(source, :gerot_tasks, target: dom_id(self))
        Turbo::StreamsChannel.broadcast_prepend_to(
          source, :gerot_tasks,
          target: task_list_id,
          partial: "tasks/task", locals: { task: self }
        )
      end
      done_tasks = bucket.tasks.where(completed: true).where.not(routine_value_id: nil)
      done_tasks = done_tasks.joins(:routine_value).where(routine_values: { routine_id: routine.id }) if source == routine
      Turbo::StreamsChannel.broadcast_update_to(
        source, :gerot_tasks, target: "done-count-#{bucket.id}",
        html: "✔️ Tarefas concluídas (#{done_tasks.count})"
      )
    end
  end

  def should_reset_due_notification?
    will_save_change_to_due_at? || will_save_change_to_due_notification_enabled?
  end

  def reset_due_notification_sent_at
    self.due_notification_sent_at = nil
    self.early_due_notification_sent_at = nil
  end

  def clone_tasklist_to(new_task)
    return if tasklist.blank? || tasklist.tasklist_items.empty?

    new_task.tasklist.update!(title: tasklist.title)
    new_task.tasklist.tasklist_items.create!(
      tasklist.tasklist_items.map do |item|
        {
          content: item.content,
          completed: false
        }
      end
    )
  end

  def notify_due_soon_if_needed
    TaskDueNotificationService.notify_if_due_soon(self)
  end
end
