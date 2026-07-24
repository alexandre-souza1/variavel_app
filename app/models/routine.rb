class Routine < ApplicationRecord
  belongs_to :routine_template

  belongs_to :created_by,
             class_name: "User"

  has_many :routine_values,
           dependent: :destroy

  enum :status, {
    draft: 0,
    open: 1,
    closed: 2,
    archived: 3
  }

  validates :period_start,
            presence: true

  validates :period_end,
            presence: true

  validate :period_end_after_start

  private

  def period_end_after_start
    return if period_end.blank? || period_start.blank?

    return if period_end >= period_start

    errors.add(:period_end, "deve ser maior que a data inicial")
  end
end
