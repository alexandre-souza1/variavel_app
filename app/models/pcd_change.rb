class PcdChange < ApplicationRecord
  belongs_to :pcd_plan
  belongs_to :user, optional: true
  validates :action, presence: true
  validates :reason, presence: true, length: { maximum: 500 }
end
