class CommonController < ApplicationController
  def home
    redirect_to dashboard_path and return if current_user&.sector_fleet?
  end

  def padroes
  end

end
