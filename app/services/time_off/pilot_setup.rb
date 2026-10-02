module TimeOff
  class PilotSetup
    def self.schedule
      TimeOffSchedule.find_or_create_by!(name: 'Piloto 5x2 • Motoristas e ajudantes') do |schedule|
        schedule.assign_attributes(starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 31),
          rotation_anchor: Date.new(2026, 9, 28), recurring: true)
      end
    end

    def self.entries
      YAML.safe_load_file(Rails.root.join('config/time_off_pilot.yml'))
    end

    def self.pending(schedule)
      linked = schedule.time_off_memberships.where.not(pilot_key: nil).pluck(:pilot_key)
      entries.reject { |entry| linked.include?(entry['key']) }
    end

    def self.call(schedule:, user: nil)
      created = 0
      schedule.with_lock do
        people = { 'driver' => People.active_records(Driver).to_a, 'helper' => People.active_records(Ajudante).to_a }
        pending(schedule).reject { |entry| entry['vacancy'] }.each do |entry|
          names = [entry['name'], entry['lookup_name']].compact.map { |name| normalize(name) }
          candidates = people.fetch(entry['role']).select do |person|
            names.include?(normalize(person.nome)) && (!entry['promax'] || person.promax.to_s.to_i == entry['promax'].to_i)
          end
          next unless candidates.one?
          person = candidates.first
          key = entry['role'] == 'driver' ? :driver_id : :ajudante_id
          next if schedule.time_off_memberships.where(key => person.id).exists?
          member = schedule.time_off_memberships.create!(key => person.id, group_code: entry['group'],
            starts_on: schedule.starts_on, pilot_key: entry['key'], fixed_weekday: entry['fixed_weekday'], standard_operation: entry['standard_operation'])
          schedule.time_off_changes.create!(time_off_membership: member, user: user, date: schedule.starts_on,
            details: { action: 'group', after: entry['group'], reason: 'Composição inicial do piloto' })
          created += 1
        end
        # Add the agreed defaults to the initial pilot links only. Later dated
        # memberships and defaults already chosen by the manager are preserved.
        entries.select { |entry| entry['standard_operation'] }.each do |entry|
          member = schedule.time_off_memberships.find_by(pilot_key: entry['key'], starts_on: schedule.starts_on, group_code: 'FIXO', fixed_weekday: 6, standard_operation: nil)
          next unless member&.active_person?
          member.update!(standard_operation: entry['standard_operation'])
          schedule.time_off_changes.create!(time_off_membership: member, user: user, date: member.starts_on,
            details: { action: 'group', before: 'FIXO', after: 'FIXO', standard_operation: member.standard_operation, reason: 'Titular da operação fixa do piloto' })
        end
      end
      { created: created, pending: pending(schedule) }
    end

    def self.normalize(name)
      ActiveSupport::Inflector.transliterate(name.to_s).upcase.strip.gsub(/\s+/, ' ')
    end
  end
end
