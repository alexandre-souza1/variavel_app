module TimeOff
  class UpdateVacation
    def self.create(schedule:, membership_id:, starts_on:, ends_on:, reason:, user:)
      schedule.with_lock do
        member = schedule.time_off_memberships.find(membership_id)
        raise UpdateDay::InvalidChange, 'Selecione um colaborador ativo para registrar férias.' unless member.active_person?
        vacation = schedule.time_off_vacations.create!(time_off_membership: member, starts_on: starts_on, ends_on: ends_on, reason: reason.to_s.strip)
        audit(schedule, vacation, user, 'vacation', vacation.reason)
        vacation
      end
    end

    def self.cancel(schedule:, id:, reason:, user:)
      raise UpdateDay::InvalidChange, 'Informe o motivo do cancelamento (até 500 caracteres).' if reason.to_s.strip.empty? || reason.to_s.size > 500
      schedule.with_lock do
        vacation = schedule.time_off_vacations.active.find(id)
        vacation.update!(cancelled_at: Time.current)
        audit(schedule, vacation, user, 'vacation_cancelled', reason.to_s.strip)
        vacation
      end
    end

    def self.audit(schedule, vacation, user, action, reason)
      schedule.time_off_changes.create!(time_off_membership: vacation.time_off_membership, user: user, date: vacation.starts_on,
        details: { action: action, vacation_id: vacation.id, starts_on: vacation.starts_on.iso8601, ends_on: vacation.ends_on.iso8601, reason: reason })
    end
    private_class_method :audit
  end
end
