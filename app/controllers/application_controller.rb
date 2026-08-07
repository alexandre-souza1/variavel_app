class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?

  helper_method :secondary_nav

  def secondary_nav
    return "admin_nav" if finance_module?
    return "fleet_nav" if fleet_module?
  end

  protected

  def finance_module?
    controller_path.in?([
      "invoices",
      "suppliers",
      "admin/budget_categories",
      "admin/cost_centers"
    ])
  end

  def fleet_module?
    controller_path.in?([
      "fleet_availabilities",
      "action_plans",
      "routines",
      "dashboards",
      "placas_por_setor",
      "plates",
    ])
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:photo])
    devise_parameter_sanitizer.permit(:account_update, keys: [:photo])
  end

  def require_admin!
    redirect_to root_path, alert: "Acesso restrito a administradores" unless current_user&.admin?
  end

  def require_admin_or_supervisor!
    return if current_user&.admin? || current_user&.supervisor?

    redirect_to root_path, alert: "Acesso negado"
  end
end
