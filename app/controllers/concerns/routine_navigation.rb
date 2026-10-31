module RoutineNavigation
  extend ActiveSupport::Concern
  include NavigationReturn

  included do
    helper_method :routine_return_path
  end

  private

  def routine_return_path
    plan = @routine.action_plan
    fallback = plan ? action_plan_path(plan, view: "gerots", year: @routine.period_start.year) : routines_path
    allowed_paths = [routines_path, archived_routines_path]
    allowed_paths << action_plan_path(plan) if plan

    safe_navigation_return_path(params[:return_to], fallback: fallback, allowed_paths: allowed_paths)
  end

  def routine_details_path
    routine_path(@routine, return_to: params[:return_to].present? ? routine_return_path : nil)
  end
end
