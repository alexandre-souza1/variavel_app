class CommonController < ApplicationController
  def home
    unless params[:force_home].present?
      # Use 303 so Turbo/browser performs a fresh GET on the dashboard. This
      # ensures the dashboard action recalculates the chart collections.
      redirect_to mechanic_tasks_path, status: :see_other and return if current_user&.mechanical?
      redirect_to dashboard_path, status: :see_other and return if current_user&.sector_fleet?
      redirect_to dashboard_mapas_path, status: :see_other and return if current_user&.sector_du?
    end
    # renderiza a home
  end

  def padroes
  end
end
