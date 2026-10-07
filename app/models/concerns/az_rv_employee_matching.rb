module AzRvEmployeeMatching
  extend ActiveSupport::Concern

  included do
    belongs_to :employee, optional: true
    before_validation :resolve_employee_identity
    scope :for_employee, ->(name) do
      key = AzRvEmployeeMatching.normalize(name)
      where("employee_key = :key OR :key LIKE employee_key || ' %'", key: key)
    end
  end

  class_methods do
    def for_person(person)
      employee = person.is_a?(Employee) ? person : person.try(:employee)
      return for_employee(person.nome) unless employee
      keys = EmployeeName.resolutions(where(employee_id: nil).distinct.pluck(:employee_key))
        .select { |_key, id| id == employee.id }.keys
      where(employee_id: employee.id).or(where(employee_id: nil, employee_key: keys))
    end
  end

  def resolve_employee_identity
    self.employee ||= EmployeeName.resolve(employee_name)
  end

  def self.normalize(name)
    name.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
        .downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end
