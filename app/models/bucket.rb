class Bucket < ApplicationRecord
  belongs_to :action_plan
  has_many :tasks, dependent: :destroy

  default_scope { order(:position) }
end
