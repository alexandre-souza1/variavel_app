module ChecklistTracking
  class RegisterTaskJob < ApplicationJob
    queue_as :default
    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

    def perform(task_id)
      task = Task.find_by(id: task_id)
      return unless task && !task.inbox? && task.creator.can_view_checklist_tracking?
      return if task.checklist_occurrences.exists?

      source = TaskSource.new(task)
      AutomaticRegistration.new(user: task.creator, tasks: Task.where(id: task.id),
        year: source.suggested_date.year, subject: source.spot? ? 'spot' : 'employees').call
    end
  end
end
