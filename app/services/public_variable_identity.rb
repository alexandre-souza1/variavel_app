class PublicVariableIdentity
  PROFILES = {
    "motorista" => Driver,
    "operador" => Operator,
    "ajudante" => Ajudante,
    "az_ajudante" => AzAjudante
  }.freeze

  LABELS = {
    "motorista" => "Motorista",
    "operador" => "Operador",
    "ajudante" => "Ajudante",
    "az_ajudante" => "Ajudante do armazém"
  }.freeze

  attr_reader :profile, :record

  def self.find(profile:, registration:, birth_date:)
    record = find_record(profile, registration, birth_date)
    new(profile, record) if record
  end

  def self.from_session(data)
    return unless data.is_a?(Hash)

    profile = data["profile"]
    model = PROFILES[profile]
    record = model&.find_by(id: data["id"])
    new(profile, record) if record
  end

  def self.find_record(profile, registration, birth_date)
    model = PROFILES[profile.to_s]
    return unless model && registration.present? && birth_date.present?

    date = Date.iso8601(birth_date.to_s)
    scope = model.where(data_nascimento: date)
    scope = scope.where(matricula: registration.to_s.strip) if model == Driver || model == Ajudante
    scope = scope.where(matricula: registration.to_i) if model == Operator || model == AzAjudante
    scope.where(active: true).first
  rescue ArgumentError
    nil
  end

  def initialize(profile, record)
    @profile = profile.to_s
    @record = record
  end

  def name
    record.nome.to_s
  end

  def registration
    record.matricula.to_s
  end

  def label
    LABELS.fetch(profile, profile.humanize)
  end

  def to_h
    { profile: profile, label: label, name: name, registration: registration, record: record }
  end
end
