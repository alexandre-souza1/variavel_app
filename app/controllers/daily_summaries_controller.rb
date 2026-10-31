class DailySummariesController < ApplicationController
  before_action :authenticate_user!

  def show
    response.headers["Cache-Control"] = "no-store, private"
    @daily_summary = current_user.daily_summaries.delivered.find(params[:id])
  end
end
