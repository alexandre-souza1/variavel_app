module ColorThemesHelper
  REFINED_DARK_THEME_KEYS = %w[blue_teal sage_teal black_mint white_tea_sage earthy_forest_hues].freeze

  def original_dark_theme_preview_key(theme)
    theme.key if theme.preserve_original_palette? && REFINED_DARK_THEME_KEYS.include?(theme.key)
  end

  def registered_color_themes
    @registered_color_themes ||= ColorTheme.order(:name).to_a
  end

  def color_theme_catalog
    @color_theme_catalog ||= begin
      catalog = User::COLOR_THEMES.to_h do |name, key|
        description, colors, light = ColorTheme::BUILTIN_PALETTES.fetch(key)
        [key, { name: name, description: description, colors: colors, light: light, dark: "#092328" }]
      end
      registered_color_themes.each do |theme|
        catalog[theme.key] = {
          name: theme.name, description: theme.description, colors: theme.palette,
          light: theme.preserve_original_palette? ? ColorTheme::BUILTIN_PALETTES.fetch(theme.key)[2] : theme.css_variables(:light).fetch("app-strong"),
          dark: theme.preserve_original_palette? ? "#092328" : theme.css_variables(:dark).fetch("app-dark-page")
        }
      end
      catalog
    end
  end

  def advertised_color_themes
    registered_color_themes.select do |theme|
      theme.promotion_enabled? && (theme.promotion_starts_on..theme.promotion_ends_on).cover?(Date.current)
    end
  end

  def registered_color_theme_styles
    registered_color_themes.map do |theme|
      rules = (theme.preserve_original_palette? ? [] : %i[light dark]).map do |mode|
        variables = theme.css_variables(mode).map { |name, value| "--#{name}: #{value};" }.join(" ")
        "html[data-bs-theme=\"#{mode}\"][data-color-theme=\"#{theme.key}\"] { #{variables} }"
      end
      rules << "html[data-color-theme=\"#{theme.key}\"] [data-decoration-theme=\"#{theme.key}\"] { display: inline-flex; }" if theme.decoration.present?
      rules << "html[data-color-theme=\"#{theme.key}\"] .theme-promo[data-theme-color-param=\"#{theme.key}\"] { display: none; }"
      rules << "html[data-color-theme=\"#{theme.key}\"] .ai-assistant__launcher { background: var(--app-button-solid); color: #fff; }" unless theme.preserve_original_palette?
      rules.join("\n")
    end.join("\n")
  end

  def theme_symbol(theme, size:)
    if theme.key == "halloween" && theme.decoration == "🎃"
      image_tag "halloween-pumpkin.svg", alt: "", width: size, height: size
    else
      tag.span(theme.decoration, class: "theme-decoration__symbol")
    end
  end
end
