class PcdPlan < ApplicationRecord
  has_many :pcd_imports, dependent: :restrict_with_exception
  has_many :pcd_changes, dependent: :restrict_with_exception
  validates :date, presence: true, uniqueness: true
end
