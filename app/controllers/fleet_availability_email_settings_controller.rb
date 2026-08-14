class FleetAvailabilityEmailSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_fleet_email_settings_access!

  def edit
    @fleet_availability_email_setting = FleetAvailabilityEmailSetting.current
  end

  def update
    @fleet_availability_email_setting = FleetAvailabilityEmailSetting.current

    if @fleet_availability_email_setting.update(fleet_availability_email_setting_params)
      purge_signature_image_if_requested

      redirect_to edit_fleet_availability_email_setting_path,
                  notice: "Configuração de e-mail salva com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def fleet_availability_email_setting_params
    params
      .require(:fleet_availability_email_setting)
      .permit(:enabled, :recipients, :cc, :bcc, :subject, :body, :signature_image)
  end

  def require_fleet_email_settings_access!
    return if current_user&.admin? || current_user&.sector_fleet?

    redirect_to root_path, alert: "Acesso restrito à frota."
  end

  def purge_signature_image_if_requested
    return unless ActiveModel::Type::Boolean.new.cast(params[:remove_signature_image])
    return unless @fleet_availability_email_setting.signature_image.attached?

    @fleet_availability_email_setting.signature_image.purge
  end
end
