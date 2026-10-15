class AiMessage < ApplicationRecord
  belongs_to :ai_conversation
  has_many :ai_action_requests, dependent: :nullify

  validates :role, inclusion: { in: %w[user assistant] }
  validates :content, presence: true, length: { maximum: 12_000 }
end
