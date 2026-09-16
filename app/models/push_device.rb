class PushDevice < ApplicationRecord
  belongs_to :user
  validates :token, presence: true, length: { maximum: 2048 }
  validates :session_binding, :last_seen_at, presence: true
end
