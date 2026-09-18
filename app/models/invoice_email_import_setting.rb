class InvoiceEmailImportSetting < ApplicationRecord
  belongs_to :purchaser, class_name: "User", optional: true
  belongs_to :budget_category, optional: true
  belongs_to :fallback_cost_center, class_name: "CostCenter", optional: true

  validates :sender_email, :imap_folder, :schedule_time, presence: true
  validate :schedule_time_is_valid

  def self.current
    first_or_create!(sender_email: "postoparadao1@gmail.com", imap_folder: "INBOX", schedule_time: "07:00")
  end

  private

  def schedule_time_is_valid
    return if schedule_time.to_s.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/)

    errors.add(:schedule_time, "deve estar no formato HH:MM")
  end
end
