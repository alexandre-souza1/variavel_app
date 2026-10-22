module ChecklistTracking
  class Exclusion
    class InvalidChange < StandardError; end

    def initialize(occurrence:, user:, reason:, details:)
      @occurrence, @user, @reason, @details = occurrence, user, reason, details.to_s.strip
    end

    def call
      label = ChecklistOccurrence::EXCLUSION_REASONS[@reason]
      raise InvalidChange, "Escolha o motivo para não contar esta ocorrência." unless label
      raise InvalidChange, "Descreva o motivo para desconsiderar a ocorrência." if @reason == "other" && @details.blank?
      raise ActiveRecord::RecordNotFound unless @user.can_view_checklist_tracking? && Employee.for_checklist_tracking(@user).exists?(@occurrence.employee_id)
      reason = [label, @details.presence].compact.join(" — ")
      ChecklistOccurrence.transaction do
        records = ChecklistOccurrence.active.where(employee_id: @occurrence.employee_id,
          occurred_on: @occurrence.occurred_on, checklist_kind: @occurrence.checklist_kind).order(:id).lock.to_a
        records.each do |record|
          record.update!(cancelled_at: Time.current, cancelled_by: @user,
            cancellation_reason: reason, exclusion_category: @reason)
          TaskActivityService.log(task: record.task, user: @user, activity_type: :updated,
            new_value: "#{record.employee.nome} · #{I18n.l(record.occurred_on)} · #{record.kind_label}",
            metadata: { field: "checklist_occurrence", action: "cancelled", occurrence_id: record.id,
                        reason: reason, exclusion_category: @reason })
        end
        records.size
      end
    end
  end
end
