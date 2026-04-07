class Label < ApplicationRecord
  belongs_to :action_plan

  has_many :task_labels
  has_many :tasks, through: :task_labels
end
