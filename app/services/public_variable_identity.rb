class PublicVariableIdentity
  PROFILES = {
    "colaborador" => Employee,
    "motorista" => Driver,
    "operador" => Operator,
    "ajudante" => Ajudante,
    "az_ajudante" => AzAjudante
  }.freeze

  LABELS = {
    "colaborador" => "Colaborador",
    "motorista" => "Motorista",
    "operador" => "Operador",
    "ajudante" => "Ajudante",
    "az_ajudante" => "Ajudante do armazém"
  }.freeze

  attr_reader :profile, :record

  def self.find(profile:, registration:, birth_date:)
    profile = profile.presence || "colaborador"
    record = find_record(profile, registration, birth_date)
    new(profile, record) if record
  end

  def self.from_session(data)
    return unless data.is_a?(Hash)

    profile = data["profile"]
    model = PROFILES[profile]
    record = model&.find_by(id: data["id"])
    new(profile, record) if record&.active? && (!record.respond_to?(:employee) || !record.employee || record.employee.active?)
  end

  def self.find_record(profile, registration, birth_date)
    model = PROFILES[profile.to_s]
    return unless model && registration.present? && birth_date.present?

    date = Date.iso8601(birth_date.to_s)
    people = Employee.active.where(data_nascimento: date, matricula: registration.to_s.strip).limit(2).to_a
    return people.first if people.one?
    return if people.many?
    models = profile.to_s == 'colaborador' ? [Driver, Ajudante, Operator, AzAjudante] : [model]
    records = models.flat_map do |klass|
      scope = klass.where(data_nascimento: date, matricula: registration.to_s.strip, active: true)
      scope = scope.where(employee_id: nil) if klass != Employee
      scope.limit(2).to_a
    end
    records.one? ? records.first : nil
  rescue ArgumentError
    nil
  end

  def initialize(profile, record)
    central = record.is_a?(Employee) ? record : record.try(:employee)
    @record = central || record
    @profile = central ? 'colaborador' : (profile.to_s == 'colaborador' ? PROFILES.key(record.class) : profile.to_s)
  end

  def name
    record.nome.to_s
  end

  def registration
    record.matricula.to_s
  end

  def label
    role = record.role_on(Date.current) if record.is_a?(Employee)
    role ? "#{role.label} · #{role.sector_label}" : LABELS.fetch(profile, profile.humanize)
  end

  def to_h
    { profile: profile, label: label, name: name, registration: registration, record: record }
  end
end
