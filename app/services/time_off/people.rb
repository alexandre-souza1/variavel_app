module TimeOff
  module People
    def self.active?(person)
      return person.active? if person.is_a?(Employee)
      person&.active? && (!person.employee || person.employee.active?)
    end

    def self.active_records(klass, date: Date.current)
      cargos = klass == Driver ? %w[motorista van] : ['ajudante']
      people = Employee.active.where(id: EmployeeRole.du.on(date).where(cargo: cargos).select(:employee_id))
      klass.active.where(employee_id: nil).or(klass.active.where(employee_id: people.select(:id)))
    end
  end
end
