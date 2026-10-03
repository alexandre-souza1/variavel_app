class PcdImport < ApplicationRecord
  belongs_to :pcd_plan
  belongs_to :user, optional: true
  validates :filename, :digest, presence: true
end
