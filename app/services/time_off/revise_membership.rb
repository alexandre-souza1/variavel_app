module TimeOff
  class ReviseMembership
    FIELDS = %w[group_code starts_on ends_on fixed_weekday standard_operation pilot_key].freeze

    def self.call(schedule:, membership_id:, starts_on:, group_code:, reason:, expected_updated_at:, user:, fixed_weekday: nil, standard_operation: nil)
      reason = reason.to_s.strip
      raise UpdateDay::InvalidChange, 'Informe o motivo da correção (até 500 caracteres).' if reason.empty? || reason.length > 500
      raise UpdateDay::InvalidChange, 'Data fora da vigência da escala.' unless schedule.covers?(starts_on)

      schedule.with_lock do
        member = schedule.time_off_memberships.find(membership_id)
        unless expected_updated_at.to_s == member.updated_at.iso8601(6)
          raise UpdateDay::Conflict, 'A vigência foi alterada por outra pessoa. Atualize a página antes de corrigir.'
        end
        raise UpdateDay::InvalidChange, 'Selecione um colaborador DU ativo.' unless member.active_person?(starts_on)
        previous = memberships_for(schedule, member).where('starts_on < ?', member.starts_on).order(starts_on: :desc).first
        if previous && starts_on <= previous.starts_on
          raise UpdateDay::InvalidChange, 'O início corrigido deve ser posterior ao início da vigência anterior.'
        end
        if member.ends_on && starts_on > member.ends_on
          raise UpdateDay::InvalidChange, 'O início corrigido deve ser igual ou anterior ao fim desta vigência.'
        end

        before = member.attributes.slice(*FIELDS)
        original_start = member.starts_on
        adjoining = previous && previous.ends_on == original_start - 1.day
        previous_before = previous.attributes.slice(*FIELDS) if adjoining
        member.assign_attributes(starts_on: starts_on, group_code: group_code,
          fixed_weekday: group_code == 'FIXO' ? fixed_weekday : nil,
          standard_operation: group_code == 'FIXO' ? standard_operation.presence : nil)
        member.pilot_key = nil if member.group_code_changed?
        raise UpdateDay::InvalidChange, 'Nenhuma alteração informada para esta vigência.' unless member.changed?

        # Shrink the period first so both updates pass overlap validation.
        previous.update!(ends_on: starts_on - 1.day) if adjoining && starts_on < original_start
        member.save!
        previous.update!(ends_on: starts_on - 1.day) if adjoining && starts_on > original_start

        archived = []
        moved = []
        periods = [previous, member].compact
        TimeOffOverride.where(time_off_membership_id: periods.map(&:id)).order(:date, :id).each do |override|
          destination = periods.find { |period| period.covers?(override.date) }
          if destination.nil?
            archived << override.attributes.slice('id', 'date', 'status', 'reason', 'lock_version')
            override.destroy!
          elsif destination.id != override.time_off_membership_id
            moved << { date: override.date, from: override.time_off_membership_id, to: destination.id }
            override.update!(time_off_membership: destination)
          end
        end
        schedule.time_off_changes.create!(time_off_membership: member, user: user, date: starts_on,
          details: { action: 'group_corrected', before: before, after: member.attributes.slice(*FIELDS), reason: reason,
            previous_membership_id: adjoining ? previous.id : nil, previous_before: previous_before,
            previous_after: adjoining ? previous.attributes.slice(*FIELDS) : nil, archived_adjustments: archived, moved_adjustments: moved })
        member
      end
    end

    def self.memberships_for(schedule, member)
      scope = schedule.time_off_memberships
      key = member.driver_id ? :driver_id : :ajudante_id
      people = scope.where(key => member.public_send(key))
      central_id = member.employee_id || member.person.employee_id
      if central_id
        people = people.or(scope.where(employee_id: central_id))
          .or(scope.where(driver_id: Driver.where(employee_id: central_id).select(:id)))
          .or(scope.where(ajudante_id: Ajudante.where(employee_id: central_id).select(:id)))
      end
      people
    end
    private_class_method :memberships_for
  end
end
