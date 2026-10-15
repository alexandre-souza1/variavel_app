class Admin::AiSettingsController < ApplicationController
  TABS = { "overview" => "Visão geral", "models" => "Modelos e cotas", "users" => "Uso por usuário", "settings" => "Configurações" }.freeze
  before_action :authenticate_user!
  before_action :require_admin!

  def edit
    @ai_setting = AiSetting.current
    prepare_dashboard
  end

  def update
    @ai_setting = AiSetting.current

    if @ai_setting.update(ai_setting_params)
      redirect_to edit_admin_ai_setting_path(tab: "settings"), notice: "Configurações de IA atualizadas com sucesso."
    else
      prepare_dashboard(tab: "settings")
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def prepare_dashboard(tab: nil)
    @tab = tab || params[:tab].presence_in(TABS.keys) || "overview"
    @usage_dashboard = GeminiUsageDashboard.new(@ai_setting)
    @usage_report = GeminiUsageReport.new(period: params[:period], metric: params[:metric], model: params[:model], feature: params[:feature])
    @user_usage = @usage_report.users(query: params[:user_query], page: params[:page]) if @tab == "users"
  end

  def ai_setting_params
    params.require(:ai_setting).permit(:primary_model, :meeting_audio_max_minutes,
      model_limits: AiSetting::MODELS.values.index_with { %i[rpm tpm rpd] })
  end
end
