class Tasklist < ApplicationRecord
  belongs_to :task
  has_many :tasklist_items, dependent: :destroy
end
