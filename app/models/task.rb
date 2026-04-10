class Task < ApplicationRecord
  belongs_to :bucket
  belongs_to :creator, class_name: "User"

  has_many :comments, dependent: :destroy
  has_many :tasklists, dependent: :destroy
  has_many :task_assignments, dependent: :destroy
  has_many :users, through: :task_assignments
  has_many :task_labels, dependent: :destroy
  has_many :labels, through: :task_labels
end
