class InvoiceEmailImport < ApplicationRecord
  belongs_to :invoice, optional: true

  validates :message_id, :sender, :status, presence: true

  scope :processed, -> { where(status: "processed") }

  def processed?
    status == "processed"
  end
end
