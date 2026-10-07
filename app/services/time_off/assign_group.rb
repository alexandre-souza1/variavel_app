module TimeOff
  class AssignGroup
    def self.call(schedule:, person:, group_code:, starts_on:, user:, fixed_weekday: nil, pilot_key: nil, standard_operation: nil)
      fixed_weekday = nil unless group_code == 'FIXO'
      raise UpdateDay::InvalidChange, 'Selecione um colaborador ativo.' unless People.active?(person)
      raise UpdateDay::InvalidChange, 'Data fora da vigência do piloto.' unless schedule.covers?(starts_on)
      employee = person.is_a?(Employee) ? person : person.employee
      if employee
        raise UpdateDay::InvalidChange, 'A escala 5×2 é exclusiva de colaboradores DU.' unless employee.eligible_for?(:time_off, date: starts_on)
        person = Employees::Registry.model_for(employee.role_on(starts_on)).where(employee_id: employee.id).first!
      end
      if pilot_key.present?
        entry = PilotSetup.entries.find { |item| item['key'] == pilot_key }
        unless entry && entry['group'] == group_code && entry['role'] == (person.is_a?(Driver) ? 'driver' : 'helper')
          raise UpdateDay::InvalidChange, 'A vaga selecionada pertence a outro grupo ou função.'
        end
      end
      schedule.with_lock do
        key = person.is_a?(Driver) ? :driver_id : :ajudante_id
        memberships = schedule.time_off_memberships.where(key => person.id)
        if employee
          memberships = memberships.or(schedule.time_off_memberships.where(employee_id: employee.id))
            .or(schedule.time_off_memberships.where(driver_id: Driver.where(employee_id: employee.id).select(:id)))
            .or(schedule.time_off_memberships.where(ajudante_id: Ajudante.where(employee_id: employee.id).select(:id)))
        end
        memberships = memberships.order(:starts_on)
        current = memberships.on(starts_on).first
        if memberships.where('starts_on > ?', starts_on).exists? || (current && current.starts_on == starts_on)
          raise UpdateDay::InvalidChange, 'Já existe uma vigência nessa data ou depois dela. Escolha uma data posterior para preservar o histórico.'
        end
        raise UpdateDay::InvalidChange, 'O colaborador já está nesse grupo e operação.' if current&.group_code == group_code && current.fixed_weekday == fixed_weekday && current.standard_operation == standard_operation.presence
        previous_group = current&.group_code
        current&.update!(ends_on: starts_on - 1.day)
        member = schedule.time_off_memberships.create!(key => person.id, group_code: group_code, starts_on: starts_on, fixed_weekday: group_code == 'FIXO' ? fixed_weekday : nil, pilot_key: pilot_key.presence, standard_operation: standard_operation.presence)
        current&.time_off_overrides&.where('date >= ?', starts_on)&.update_all(time_off_membership_id: member.id)
        schedule.time_off_changes.create!(time_off_membership: member, user: user, date: starts_on,
          details: { action: 'group', before: previous_group, after: group_code, reason: 'Definição de grupo e operação', fixed_weekday: member.fixed_weekday, standard_operation: member.standard_operation })
        member
      end
    end
  end
end
