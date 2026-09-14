class Admin::AiSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def edit
    @ai_setting = AiSetting.current
  end

  def update
    @ai_setting = AiSetting.current

    if @ai_setting.update(ai_setting_params)
      redirect_to edit_admin_ai_setting_path, notice: "Configurações de IA atualizadas com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def ai_setting_params
    params.require(:ai_setting).permit(:primary_model, :meeting_audio_max_minutes)
  end
end
