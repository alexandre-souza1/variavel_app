class InboxesController < ApplicationController
  before_action :authenticate_user!

  def show
    @inbox_bucket = current_user.personal_inbox!
    @inbox_tasks = @inbox_bucket.tasks.includes(:users, :labels).order(:position)
    @task_to_open = @inbox_tasks.find_by(id: params[:task_id])
  end
end
