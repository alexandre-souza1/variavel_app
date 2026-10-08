module TimeOff
  class DeleteMembership
    def self.call(schedule:, membership_id:, reason:, expected_updated_at:, user:)
      reason = reason.to_s.strip
      raise UpdateDay::InvalidChange, 'Informe o motivo da exclusão (até 500 caracteres).' if reason.empty? || reason.length > 500
      schedule.with_lock do
        member = schedule.time_off_memberships.find(membership_id)
        unless expected_updated_at.to_s == member.updated_at.iso8601(6)
          raise UpdateDay::Conflict, 'A vigência foi alterada por outra pessoa. Atualize a página antes de excluir.'
        end
        before = member.attributes.slice(*ReviseMembership::FIELDS)
        archived = member.time_off_overrides.order(:date).map { |override| override.attributes.slice('id', 'date', 'status', 'reason', 'lock_version') }
        member.update!(cancelled_at: Time.current, pilot_key: nil)
        schedule.time_off_changes.create!(time_off_membership: member, user: user, date: member.starts_on,
          details: { action: 'group_deleted', before: before, reason: reason, cancelled_at: member.cancelled_at,
            person_name: member.person.nome, archived_adjustments: archived })
        member
      end
    end
  end
end
