class TimeOffMembership < ApplicationRecord
  STANDARD_OPERATIONS = { 'Vespertina' => 'vespertina', 'AS' => 'as' }.freeze
  belongs_to :time_off_schedule
  belongs_to :driver, optional: true
  belongs_to :ajudante, optional: true
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
    where(driver_id: TimeOff::People.active_records(Driver).select(:id))
      .or(where(ajudante_id: TimeOff::People.active_records(Ajudante).select(:id)))
  }

  def active_person?
    TimeOff::People.active?(person)
  end

  def person
    driver || ajudante
  end

  def role
    driver_id? ? 'driver' : 'helper'
  end

  def role_label
    driver_id? ? 'Motorista' : 'Ajudante'
  end

  def covers?(date)
    starts_on && date >= starts_on && (ends_on.nil? || date <= ends_on)
  end

  def cargo_on(date)
    if person.employee
      person.employee.role_on(date)&.cargo
    else
      driver_id? ? 'motorista' : 'ajudante'
    end
  end

  def person_key
    person.employee_id ? "employee:#{person.employee_id}" : "#{role}:#{person.id}"
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
  end

  def no_overlap
    return unless time_off_schedule_id && starts_on && (driver_id || ajudante_id)
    key = driver_id ? :driver_id : :ajudante_id
    same_person = self.class.where(key => public_send(key))
    if person&.employee_id
      same_person = same_person.or(self.class.where(driver_id: Driver.where(employee_id: person.employee_id).select(:id)))
        .or(self.class.where(ajudante_id: Ajudante.where(employee_id: person.employee_id).select(:id)))
    end
    overlap = same_person.where(time_off_schedule_id: time_off_schedule_id).where.not(id: id).where('ends_on IS NULL OR ends_on >= ?', starts_on)
    overlap = overlap.where('starts_on <= ?', ends_on) if ends_on
    errors.add(:base, 'O colaborador já pertence a um grupo nesse período') if overlap.exists?
  end
end
