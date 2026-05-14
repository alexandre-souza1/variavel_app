class ChecklistDefect < ApplicationRecord
  belongs_to :checklist

  validates :description, presence: true
end