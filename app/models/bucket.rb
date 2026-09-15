class Bucket < ApplicationRecord
  belongs_to :action_plan
  has_many :tasks, dependent: :destroy

  scope :work, -> { where(inbox: false) }

  default_scope { order(:position) }

  def open_count
    tasks.where(completed: false).count
  end

  def done_count
    tasks.where(completed: true).count
  end
end
