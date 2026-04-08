class Comment < ApplicationRecord
  belongs_to :task
  belongs_to :user


  after_create_commit -> {
    broadcast_append_to "comments_task_#{task.id}",
    target: "comments_task_#{task.id}",
    partial: "comments/comment",
    locals: { comment: self }
  }
end
