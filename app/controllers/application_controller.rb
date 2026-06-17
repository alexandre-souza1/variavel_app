class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

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
