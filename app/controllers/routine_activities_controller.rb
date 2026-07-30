class RoutineActivitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine

  def index
    @activities = @routine
      .routine_activities
      .includes(
        :user,
        routine_value: :routine_indicator
      )
      .order(created_at: :desc)
      .limit(100)
  end

  private

  def set_routine
    @routine = Routine.find(params[:routine_id])
  end
end
