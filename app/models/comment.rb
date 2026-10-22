class Comment < ApplicationRecord
  belongs_to :task
  belongs_to :user
  after_commit -> { task&.enqueue_checklist_tracking }, on: %i[create update]

  after_create_commit -> {
    broadcast_append_to task.feed_stream,
      target: "task_feed_#{task.id}",
      partial: "comments/comment",
      locals: { comment: self }
  }
end
