class EmployeeRole < ApplicationRecord
  class HistoryError < StandardError; end
  CARGOS = { 'Ajudante' => 'ajudante', 'Motorista de van' => 'van', 'Motorista' => 'motorista' }.freeze
  belongs_to :employee
  belongs_to :created_by, class_name: 'User', optional: true
  validates :cargo, inclusion: { in: CARGOS.values }
  validates :promax, :reason, presence: true
  validates :starts_on, presence: true, unless: :legacy?
  validate :valid_interval
  validate :unique_code_owner
  before_validation { self.promax = promax.to_s.strip }

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

  def valid_interval
    errors.add(:ends_on, 'deve ser posterior ou igual ao início') if starts_on && ends_on && ends_on < starts_on
    overlaps = self.class.where(employee_id: employee_id).where.not(id: id)
    overlaps = overlaps.where('ends_on IS NULL OR ends_on >= ?', starts_on) if starts_on
    overlaps = overlaps.where('starts_on IS NULL OR starts_on <= ?', ends_on) if ends_on
    errors.add(:base, 'Existe outro cargo vigente nesse período') if overlaps.exists?
  end
end
