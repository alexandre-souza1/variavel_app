module TimeOff
  class GroupRoster
    attr_reader :people, :memberships

    def initialize(schedule:, date:)
      @people = Employee.active.in_sector('du', date: date).includes(:employee_roles).order(:nome).to_a
      @people += People.active_records(Driver, date: date).where(employee_id: nil).order(:nome).to_a
      @people += People.active_records(Ajudante, date: date).where(employee_id: nil).order(:nome).to_a
      @memberships = self.class.memberships(schedule: schedule, date: date)
    end

    def self.key(person)
      "#{person.is_a?(Employee) ? 'employee' : person.is_a?(Driver) ? 'driver' : 'helper'}:#{person.id}"
    end

    def self.memberships(schedule:, date:, employee_ids: nil)
      return {} unless schedule
      scope = schedule.time_off_memberships.on(date).with_active_people
      if employee_ids
        scope = scope.where(employee_id: employee_ids)
          .or(scope.where(driver_id: Driver.where(employee_id: employee_ids).select(:id)))
          .or(scope.where(ajudante_id: Ajudante.where(employee_id: employee_ids).select(:id)))
      end
      scope
        .includes(:employee, driver: :employee, ajudante: :employee)
        .index_by(&:person_key)
    end

    def unassigned
      people.reject { |person| memberships.key?(self.class.key(person)) }
    end
  end
end
