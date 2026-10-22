module ChecklistTracking
  class History
    def initialize(scope:)
      @scope = scope
    end

    def events
      @scope.includes(:employee, :recorded_by, :cancelled_by, task: [:users, :labels, { bucket: :action_plan }, { routine_value: :routine }])
        .order(occurred_on: :desc, id: :desc).to_a
        .group_by { |record| [record.employee_id, record.occurred_on, record.checklist_kind] }.map do |_, records|
          active = records.reject(&:cancelled_at?)
          { employee: records.first.employee, date: records.first.occurred_on, kind: records.first.kind_label,
            sources: records, excluded: active.empty?, completed: active.any? && active.all? { |record| record.task.completed? } }
        end
    end
  end
end
