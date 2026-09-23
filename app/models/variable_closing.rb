class VariableClosing < ApplicationRecord
  belongs_to :employee
  belongs_to :user, optional: true
  validates :user, presence: true, unless: :legacy_baseline?
  validates :reason, :result, presence: true
  validates :month, inclusion: { in: 1..12 }
  validates :year, numericality: { only_integer: true, greater_than: 1900, less_than: 10000 }
  def readonly? = persisted?

  def self.capture!(employee:, user:, year:, month:, reason:)
    employee.with_lock do
      finish = Date.new(year, month, 20)
      start = finish.prev_month.change(day: 21)
      report = EmployeeVariableReport.new(employee, from: start, to: finish)
      report.validate!
      create!(employee: employee, user: user, year: year, month: month, reason: reason,
        revision: where(employee: employee, year: year, month: month).maximum(:revision).to_i + 1,
        result: report.snapshot)
    end
  end
end
