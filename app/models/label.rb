class Label < ApplicationRecord
  belongs_to :action_plan

  has_many :task_labels
  has_many :tasks, through: :task_labels
  has_many :routine_indicator_labels, dependent: :destroy
  has_many :routine_indicators, through: :routine_indicator_labels

  validates :name, presence: true
  validates :color, presence: true
  validates :name, uniqueness: { scope: :action_plan_id }
end
