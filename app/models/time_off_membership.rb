class TimeOffMembership < ApplicationRecord
  STANDARD_OPERATIONS = { 'Vespertina' => 'vespertina', 'AS' => 'as' }.freeze
  belongs_to :time_off_schedule
  belongs_to :driver, optional: true
  belongs_to :ajudante, optional: true
  belongs_to :employee, optional: true
  before_validation { self.employee ||= (driver || ajudante)&.employee }
  has_many :time_off_overrides, dependent: :restrict_with_exception
  has_many :time_off_changes, dependent: :restrict_with_exception
  has_many :time_off_vacations, dependent: :restrict_with_exception
  validates :pilot_key, uniqueness: { scope: :time_off_schedule_id }, allow_nil: true
  validates :group_code, inclusion: { in: TimeOffSchedule::GROUPS }
  validates :starts_on, presence: true
  validates :fixed_weekday, inclusion: { in: 1..6 }, allow_nil: true
  validate :valid_person_and_period
  validate :no_overlap
  validate :valid_standard_operation

  scope :on, ->(date) { where('starts_on <= ? AND (ends_on IS NULL OR ends_on >= ?)', date, date) }
  scope :during, ->(first, last) { where('starts_on <= ? AND (ends_on IS NULL OR ends_on >= ?)', last, first) }
  scope :with_active_people, -> {
    where(employee_id: Employee.active.select(:id))
      .or(where(employee_id: nil, driver_id: Driver.active.where(employee_id: nil).or(Driver.active.where(employee_id: Employee.active.select(:id))).select(:id)))
      .or(where(employee_id: nil, ajudante_id: Ajudante.active.where(employee_id: nil).or(Ajudante.active.where(employee_id: Employee.active.select(:id))).select(:id)))
  }

  def active_person?(date = Date.current)
    central = employee || person&.employee
    central ? (central.active? && (central.employee_roles.empty? || central.eligible_for?(:time_off, date: date))) : TimeOff::People.active?(person)
  end

  def person
    driver || ajudante
  end

  def role(date = Date.current)
    (employee || person&.employee) ? (cargo_on(date) == 'ajudante' ? 'helper' : 'driver') : (driver_id? ? 'driver' : 'helper')
  end

  def role_label(date = Date.current)
    EmployeeRole::DU_CARGOS.key(cargo_on(date)) || (driver_id? ? 'Motorista' : 'Ajudante')
  end

  def covers?(date)
    starts_on && date >= starts_on && (ends_on.nil? || date <= ends_on)
  end

  def cargo_on(date)
    if employee || person.employee
      assigned = (employee || person.employee).role_on(date)
      assigned&.du? ? assigned.cargo : ((employee || person.employee).employee_roles.empty? ? (driver_id? ? 'motorista' : 'ajudante') : nil)
    else
      driver_id? ? 'motorista' : 'ajudante'
    end
  end

  def person_key
    central_id = employee_id || person.employee_id
    central_id ? "employee:#{central_id}" : "#{role}:#{person.id}"
  end

  def code_on(date)
    central = employee || person.employee
    central ? central.role_on(date)&.promax : person.promax
  end

  private

  def valid_standard_operation
    return if standard_operation.blank?
    unless STANDARD_OPERATIONS.value?(standard_operation) && group_code == 'FIXO' && fixed_weekday == 6 && (standard_operation != 'as' || driver_id?)
      errors.add(:standard_operation, 'exige grupo Fixo com folga no sábado; AS exige motorista')
    end
  end

  def valid_person_and_period
    errors.add(:base, 'Selecione um motorista ou um ajudante') unless driver_id.present? ^ ajudante_id.present?
    errors.add(:ends_on, 'deve ser posterior ao início') if ends_on && starts_on && ends_on < starts_on
    if employee && starts_on
      errors.add(:base, 'A escala 5×2 exige vínculo DU na data inicial.') unless employee.employee_roles.empty? || employee.role_on(starts_on)&.du?
      errors.add(:base, 'O cadastro operacional pertence a outro colaborador.') if person&.employee_id && person.employee_id != employee_id
    end
  end

  def no_overlap
    return unless time_off_schedule_id && starts_on && (driver_id || ajudante_id)
    key = driver_id ? :driver_id : :ajudante_id
    same_person = self.class.where(key => public_send(key))
    central_id = employee_id || person&.employee_id
    if central_id
      same_person = same_person.or(self.class.where(employee_id: central_id))
        .or(self.class.where(driver_id: Driver.where(employee_id: central_id).select(:id)))
        .or(self.class.where(ajudante_id: Ajudante.where(employee_id: central_id).select(:id)))
    end
    overlap = same_person.where(time_off_schedule_id: time_off_schedule_id).where.not(id: id).where('ends_on IS NULL OR ends_on >= ?', starts_on)
    overlap = overlap.where('starts_on <= ?', ends_on) if ends_on
    errors.add(:base, 'O colaborador já pertence a um grupo nesse período') if overlap.exists?
  end
end
