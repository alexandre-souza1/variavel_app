module ChecklistTracking
  class History
    def initialize(scope:)
      @scope = scope
    end

    def events
      @scope.includes(:recorded_by, :cancelled_by, employee: :employee_roles, task: [:users, :labels, { bucket: :action_plan }, { routine_value: :routine }])
        .order(occurred_on: :desc, id: :desc).to_a
        .group_by { |record| [record.subject_key, record.occurred_on, record.checklist_kind] }.map do |_, records|
          restriction = records.first.role_restriction_reason
          active = restriction ? [] : records.reject(&:cancelled_at?)
          { employee: records.first.employee, spot_plate: records.first.spot_plate, subject_key: records.first.subject_key, name: records.first.subject_name, date: records.first.occurred_on, kind: records.first.kind_label,
            sources: records, role_restriction: restriction, excluded: active.empty?, completed: active.any? && active.all? { |record| record.task.completed? } }
        end
    end
  end
end
