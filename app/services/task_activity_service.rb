class TaskActivityService
  def self.log(task:, user:, activity_type:, old_value: nil, new_value: nil, metadata: {})
    TaskActivity.create!(
      task: task,
      user: user,
      activity_type: activity_type,
      old_value: old_value,
      new_value: new_value,
      metadata: metadata
    )
  end
end
