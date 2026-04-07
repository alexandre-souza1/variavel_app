class Task < ApplicationRecord
  belongs_to :bucket
  belongs_to :creator, class_name: "User"
  belongs_to :assignee, class_name: "User", optional: true

  has_many :comments, dependent: :destroy
  has_many :tasklists, dependent: :destroy

  has_many :task_labels, dependent: :destroy
  has_many :labels, through: :task_labels
end
