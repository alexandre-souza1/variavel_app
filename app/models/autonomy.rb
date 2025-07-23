class Autonomy < ApplicationRecord
  has_one_attached :evidence
  belongs_to :user, polymorphic: true
end
