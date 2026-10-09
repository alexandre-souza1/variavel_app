class EmployeeRole < ApplicationRecord
  class HistoryError < StandardError; end
  DU_CARGOS = { 'Ajudante' => 'ajudante', 'Motorista de van' => 'van', 'Motorista' => 'motorista' }.freeze
  AZ_CARGOS = { 'Ajudante' => 'ajudante', 'Operador' => 'operador' }.freeze
  CARGOS = DU_CARGOS.merge(AZ_CARGOS).freeze
  SECTORS = { 'DU' => 'du', 'AZ' => 'az' }.freeze
  TURNOS = { 'A' => 0, 'B' => 1, 'C' => 2 }.freeze
  PROGRESSAO = { 'ajudante' => %w[van motorista], 'van' => %w[motorista], 'motorista' => [] }.freeze

  belongs_to :employee
  belongs_to :created_by, class_name: 'User', optional: true
  scope :du, -> { where(sector: 'du') }
  scope :az, -> { where(sector: 'az') }
  scope :on, ->(date) { where(pending_start: false).where('(starts_on IS NULL OR starts_on <= ?) AND (ends_on IS NULL OR ends_on >= ?)', date, date) }
  scope :during, ->(first, last) { where(pending_start: false).where('(starts_on IS NULL OR starts_on <= ?) AND (ends_on IS NULL OR ends_on >= ?)', last, first) }

  # The RH directory includes people awaiting their first operational day,
  # while transfers keep the latest sector that has already started.
  def self.for_directory(date: Date.current)
    quoted_date = connection.quote(date)
    selected = select('DISTINCT ON (employee_id) id').order(Arel.sql(<<~SQL.squish))
      employee_id,
      CASE WHEN starts_on IS NULL OR starts_on <= #{quoted_date} THEN 0 ELSE 1 END,
      CASE WHEN starts_on <= #{quoted_date} THEN starts_on END DESC NULLS LAST,
      starts_on ASC NULLS FIRST, id DESC
    SQL
    where(id: selected)
  end

  validates :sector, inclusion: { in: SECTORS.values }
  validates :cargo, inclusion: { in: ->(role) { cargos_for(role.sector).values } }
  validates :reason, presence: true
  validates :promax, presence: true, if: -> { du? && !pending_start? }
  validates :turno, inclusion: { in: TURNOS.values }, if: -> { az? && !(turno.nil? && (legacy? || pending_start?)) }
  validates :starts_on, presence: true, unless: -> { legacy? || pending_start? }
  validate :valid_interval
  validate :valid_employment_dates
  validate :unique_code_owner
  validate :valid_progression
  before_validation do
    self.promax = du? ? promax.to_s.strip.presence : nil
    self.turno = nil if du?
  end
  after_save { Employees::Registry.synchronize!(employee) }

  def self.cargos_for(sector) = sector == 'az' ? AZ_CARGOS : DU_CARGOS
  def self.next_cargos(cargo, sector: 'du') = sector == 'az' ? AZ_CARGOS.values : PROGRESSAO.fetch(cargo.to_s, DU_CARGOS.values)
  def du? = sector == 'du'
  def az? = sector == 'az'
  def label = self.class.cargos_for(sector).key(cargo)
  def sector_label = SECTORS.key(sector)
  def shift_label = TURNOS.key(turno)
  def profile = az? ? (cargo == 'operador' ? 'operador' : 'az_ajudante') : cargo

  def covers?(date)
    !pending_start? && date && (starts_on.nil? || starts_on <= date) && (ends_on.nil? || date <= ends_on)
  end

  def follows?(previous)
    return true unless previous
    return true if sector != previous.sector
    return true if az? && (cargo != previous.cargo || turno != previous.turno)
    return true if du? && cargo == previous.cargo && promax != previous.promax
    du? && PROGRESSAO.fetch(previous.cargo, []).include?(cargo)
  end

  def matches_map?(mapa)
    return false unless du?
    codes = cargo == 'ajudante' ? [mapa.matric_ajudante, mapa.matric_ajudante_2] : [mapa.matric_motorista]
    codes.map(&:to_s).include?(promax)
  end

  private

  def valid_employment_dates
    if starts_on && employee&.registered_on && starts_on < employee.registered_on
      errors.add(:starts_on, 'deve ser igual ou posterior à data de registro na carteira')
    end
    return unless pending_start?

    errors.add(:base, 'Um cargo em integração não pode ter datas de vigência nem ser legado') if starts_on || ends_on || legacy?
    if employee && employee.employee_roles.where.not(id: id).exists?
      errors.add(:base, 'A integração só pode ser registrada no cargo inicial')
    end
  end

  def unique_code_owner
    return unless du? && promax.present? && employee_id
    cargos = cargo == 'ajudante' ? ['ajudante'] : %w[motorista van]
    overlaps = self.class.du.where(promax: promax, cargo: cargos).where.not(employee_id: employee_id)
    overlaps = overlaps.where('ends_on IS NULL OR ends_on >= ?', starts_on) if starts_on
    overlaps = overlaps.where('starts_on IS NULL OR starts_on <= ?', ends_on) if ends_on
    errors.add(:promax, 'já pertence a outro colaborador nesse período; revise os vínculos no RH') if overlaps.exists?
  end

  def valid_progression
    return if employee_id.nil? || starts_on.nil?
    previous = employee.employee_roles.where.not(id: id).to_a
      .select { |role| role.starts_on.nil? || role.starts_on < starts_on }
      .max_by { |role| role.starts_on || Date.new(1, 1, 1) }
    errors.add(:cargo, "não pode seguir #{previous.label} sem mudança de setor, código ou turno") unless follows?(previous)
  end

  def valid_interval
    errors.add(:ends_on, 'deve ser posterior ou igual ao início') if starts_on && ends_on && ends_on < starts_on
    overlaps = self.class.where(employee_id: employee_id).where.not(id: id)
    overlaps = overlaps.where('ends_on IS NULL OR ends_on >= ?', starts_on) if starts_on
    overlaps = overlaps.where('starts_on IS NULL OR starts_on <= ?', ends_on) if ends_on
    errors.add(:base, 'Existe outro cargo ou vínculo vigente nesse período') if overlaps.exists?
  end
end
