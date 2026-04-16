class Tasklist < ApplicationRecord
  belongs_to :task
  has_many :tasklist_items, dependent: :destroy

  accepts_nested_attributes_for :tasklist_items, allow_destroy: true
end
