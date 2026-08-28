class FleetAvailabilitySettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_fleet_settings_access!

  def edit
    @fleet_availability_setting = FleetAvailabilitySetting.current
  end

  def update
    @fleet_availability_setting = FleetAvailabilitySetting.current

    if @fleet_availability_setting.update(fleet_availability_setting_params)
      redirect_to fleet_availabilities_path,
                  notice: "Configuração da disponibilidade salva com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def fleet_availability_setting_params
    params.require(:fleet_availability_setting)
          .permit(:auto_lock_time, :auto_open_time)
  end

  def require_fleet_settings_access!
    return if current_user&.admin? || current_user&.sector_fleet?

    redirect_to root_path, alert: "Acesso restrito à frota."
  end
end
