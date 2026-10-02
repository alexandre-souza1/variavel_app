module TimeOff
  class UpdateDay
    class Conflict < StandardError; end
    class InvalidChange < StandardError; end

    def self.call(schedule:, membership_id:, date:, status:, reason:, expected_revision:, user:)
      raise InvalidChange, 'Informe o motivo da alteração (até 500 caracteres).' if reason.to_s.strip.empty? || reason.to_s.length > 500
      raise InvalidChange, 'Situação inválida.' unless %w[working off unavailable original].include?(status)
      schedule.with_lock do
        member = schedule.time_off_memberships.find(membership_id)
        raise InvalidChange, 'Colaborador inativo não pode ser alterado na escala.' unless member.active_person?
        base = schedule.base_status(member, date)
        raise InvalidChange, 'Data fora da vigência da escala ou do grupo.' unless base
        if Availability.new(schedule: schedule, first: date).vacation(member, date)
          raise InvalidChange, 'Colaborador está de férias. Ajuste o período nas configurações antes de alterar a disponibilidade.'
        end
        raise InvalidChange, 'Defina primeiro o dia de folga do grupo fixo.' if base == 'pending'
        raise InvalidChange, 'Domingos são DSR para todos.' if date.sunday?
        override = member.time_off_overrides.find_by(date: date)
        revision = override&.lock_version || -1
        raise Conflict, 'A escala foi alterada por outra pessoa. Atualize a página antes de continuar.' unless expected_revision.to_s == revision.to_s
        before = override&.status || base
        # Keep the override row when restoring the rotation: its revision must
        # continue increasing so stale edits cannot overwrite a newer change.
        override ||= member.time_off_overrides.build(date: date)
        override.update!(status: status == 'original' ? base : status, reason: reason.strip)
        schedule.time_off_changes.create!(time_off_membership: member, user: user, date: date,
          details: { action: 'day', before: before, after: override.status, reason: reason.strip, restored: status == 'original' })
        override
      end
    end
  end
end
