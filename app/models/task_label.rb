class TaskLabel < ApplicationRecord
  belongs_to :task
  belongs_to :label
  validate :label_belongs_to_task_plan

  private

  def label_belongs_to_task_plan
    return unless task && label
    return if !task.inbox? && label.action_plan_id == task.bucket&.action_plan_id

    errors.add(:label, "deve pertencer ao plano da tarefa")
  end
end
