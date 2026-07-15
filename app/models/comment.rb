class Comment < ApplicationRecord
  belongs_to :task
  belongs_to :user

  after_create_commit -> {
    broadcast_append_to "task_feed_#{task.id}",
      target: "task_feed_#{task.id}",
      partial: "comments/comment",
      locals: { comment: self }
  }
end
