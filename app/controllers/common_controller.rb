class CommonController < ApplicationController
  def home
    unless params[:force_home].present?
      redirect_to dashboard_path and return if current_user&.sector_fleet?
      redirect_to dashboard_mapas_path and return if current_user&.sector_du?
    end
    # renderiza a home
  end

  def padroes
  end
end