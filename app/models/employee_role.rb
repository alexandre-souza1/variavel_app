class EmployeeRole < ApplicationRecord
  class HistoryError < StandardError; end
  CARGOS = { 'Ajudante' => 'ajudante', 'Motorista de van' => 'van', 'Motorista' => 'motorista' }.freeze
  PROGRESSAO = {
    'ajudante' => %w[van motorista],
    'van' => %w[motorista],
    'motorista' => []
  }.freeze
  belongs_to :employee
  belongs_to :created_by, class_name: 'User', optional: true
  validates :cargo, inclusion: { in: CARGOS.values }
  validates :promax, :reason, presence: true
  validates :starts_on, presence: true, unless: :legacy?
  validate :valid_interval
  validate :unique_code_owner
  validate :valid_progression
  before_validation { self.promax = promax.to_s.strip }

  def self.next_cargos(cargo)
    PROGRESSAO.fetch(cargo.to_s, CARGOS.values)
  end

  def covers?(date)
    date && (starts_on.nil? || starts_on <= date) && (ends_on.nil? || date <= ends_on)
  end

  def matches_map?(mapa)
    codes = cargo == 'ajudante' ? [mapa.matric_ajudante, mapa.matric_ajudante_2] : [mapa.matric_motorista]
    codes.map(&:to_s).include?(promax)
  end

  def label
    CARGOS.key(cargo)
  end

  private

  def unique_code_owner
    return if promax.blank? || employee_id.nil?
    cargos = cargo == 'ajudante' ? ['ajudante'] : %w[motorista van]
    overlaps = self.class.where(promax: promax, cargo: cargos).where.not(employee_id: employee_id)
    overlaps = overlaps.where('ends_on IS NULL OR ends_on >= ?', starts_on) if starts_on
    overlaps = overlaps.where('starts_on IS NULL OR starts_on <= ?', ends_on) if ends_on
    errors.add(:promax, 'já pertence a outro colaborador nesse período; revise os vínculos no RH') if overlaps.exists?
  end

  def valid_progression
    return if employee_id.nil? || starts_on.nil?

    previous = employee.employee_roles.where.not(id: id).to_a
      .select { |role| role.starts_on.nil? || role.starts_on < starts_on }
      .max_by { |role| role.starts_on || Date.new(1, 1, 1) }
    return unless previous
    return if PROGRESSAO.fetch(previous.cargo, []).include?(cargo)

    errors.add(:cargo, "não pode seguir #{previous.label}. Próximos cargos permitidos: #{PROGRESSAO.fetch(previous.cargo, []).map { |value| CARGOS.key(value) }.to_sentence}")
  end

  def valid_interval
    errors.add(:ends_on, 'deve ser posterior ou igual ao início') if starts_on && ends_on && ends_on < starts_on
    overlaps = self.class.where(employee_id: employee_id).where.not(id: id)
    overlaps = overlaps.where('ends_on IS NULL OR ends_on >= ?', starts_on) if starts_on
    overlaps = overlaps.where('starts_on IS NULL OR starts_on <= ?', ends_on) if ends_on
    errors.add(:base, 'Existe outro cargo vigente nesse período') if overlaps.exists?
  end
end
