class Admin::ColorThemesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_color_theme, only: %i[edit update destroy]

  def index
    @color_themes = ColorTheme.order(:name)
  end

  def new
    @color_theme = ColorTheme.new(base_color: "#522D60", primary_color: "#80426E",
      accent_color: "#F2A67B", highlight_color: "#FFD38B")
  end

  def create
    @color_theme = ColorTheme.new(color_theme_params)
    if @color_theme.save
      redirect_to admin_color_themes_path, notice: "Tema cadastrado e disponível para os usuários.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def generate
    response.headers["Cache-Control"] = "no-store, private"
    theme = GeminiThemeService.new(colors: params[:colors], user: current_user).call
    render json: { theme: theme }
  rescue GeminiThemeService::InvalidColors => error
    render json: { error: error.message }, status: :unprocessable_entity
  rescue GeminiThemeService::Unavailable => error
    render json: { error: error.message }, status: error.reason == :quota ? :too_many_requests : :service_unavailable
  rescue StandardError => error
    Rails.logger.error("Falha ao gerar tema com IA: #{error.class.name}")
    render json: { error: "Não foi possível gerar o tema agora. Tente novamente em instantes." }, status: :service_unavailable
  end

  def update
    if @color_theme.update(color_theme_params)
      redirect_to admin_color_themes_path, notice: "Tema atualizado.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @color_theme.destroy
      redirect_to admin_color_themes_path, notice: "Tema excluído. Quem o utilizava voltou ao Blue-Teal.", status: :see_other
    else
      redirect_to admin_color_themes_path, alert: @color_theme.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def set_color_theme
    @color_theme = ColorTheme.find(params[:id])
  end

  def color_theme_params
    params.require(:color_theme).permit(:name, :description, :base_color, :primary_color,
      :accent_color, :highlight_color, :extra_color, :decoration, :promotion_enabled, :promotion_text,
      :promotion_starts_on, :promotion_ends_on, *ColorTheme::HEADER_DECORATION_FIELDS)
  end
end
