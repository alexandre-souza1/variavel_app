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
      raise ActiveRecord::RecordNotFound unless @user.can_view_checklist_tracking? && ChecklistOccurrence.visible_to(@user).exists?(@occurrence.id)
      reason = [label, @details.presence].compact.join(" — ")
      ChecklistOccurrence.transaction do
        scope = ChecklistOccurrence.active.where(@occurrence.subject_attributes).where(occurred_on: @occurrence.occurred_on, checklist_kind: @occurrence.checklist_kind)
        scope = scope.where(id: ChecklistOccurrence.visible_to(@user).select(:id)) if @occurrence.spot?
        records = scope.order(:id).lock.to_a
        records.each do |record|
          record.update!(cancelled_at: Time.current, cancelled_by: @user,
            cancellation_reason: reason, exclusion_category: @reason)
          TaskActivityService.log(task: record.task, user: @user, activity_type: :updated,
            new_value: "#{record.subject_name} · #{I18n.l(record.occurred_on)} · #{record.kind_label}",
            metadata: { field: "checklist_occurrence", action: "cancelled", occurrence_id: record.id,
                        reason: reason, exclusion_category: @reason })
        end
        records.size
      end
    end
  end
end
