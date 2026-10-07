module ConsultationNavigation
  extend ActiveSupport::Concern
  include NavigationReturn

  included do
    helper_method :consultation_return_path
  end

  private

  def consultation_return_path
    fallback = controller_name == "az_consultas" ? az_consultas_new_path : consultas_new_path
    safe_navigation_return_path(params[:return_to], fallback: fallback,
      allowed_paths: [consultas_new_path, az_consultas_new_path, variaveis_path,
        dashboard_mapas_path, dashboard_az_path])
  end
end
