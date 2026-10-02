module TimeOff
  module People
    def self.active?(person)
      person&.active? && (!person.employee || person.employee.active?)
    end

    def self.active_records(klass)
      klass.active.where(employee_id: nil).or(klass.active.where(employee_id: Employee.active.select(:id)))
    end
  end
end
