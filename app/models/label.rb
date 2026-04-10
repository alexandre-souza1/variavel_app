class Label < ApplicationRecord
  belongs_to :action_plan

  has_many :task_labels
  has_many :tasks, through: :task_labels

  validates :name, presence: true
  validates :color, presence: true
  validates :name, uniqueness: true
end
