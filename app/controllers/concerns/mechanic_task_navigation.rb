module MechanicTaskNavigation
  extend ActiveSupport::Concern

  private

  def mechanic_tasks_return_path
    filters = params.fetch(:mechanic_filters, ActionController::Parameters.new)
      .permit(:status, :view, :q, :action_plan_id, label_ids: [])
    mechanic_tasks_path(filters.to_h)
  end
end
