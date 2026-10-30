module ColorThemesHelper
  REFINED_DARK_THEME_KEYS = %w[blue_teal sage_teal black_mint white_tea_sage earthy_forest_hues].freeze
  PANEL_DECORATION_ICONS = { "🎃" => "Abóbora", "👻" => "Fantasminha", "🦇" => "Morcego", "✦" => "Brilho",
    "⭐" => "Estrela", "🎄" => "Árvore de Natal", "❄️" => "Floco de neve", "🎁" => "Presente", "🍂" => "Folhas de outono" }.freeze

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
      if theme.decoration.present?
        rules << "html[data-color-theme=\"#{theme.key}\"] [data-decoration-theme=\"#{theme.key}\"] { display: inline-flex; }"
      end
      decoration = panel_decoration_styles(theme)
      rules << "html[data-color-theme=\"#{theme.key}\"] { #{decoration} }" if decoration.present?
      rules << "html[data-color-theme=\"#{theme.key}\"] .theme-promo[data-theme-color-param=\"#{theme.key}\"] { display: none; }"
      rules << "html[data-color-theme=\"#{theme.key}\"] .ai-assistant__launcher { background: var(--app-button-solid); color: #fff; }" unless theme.preserve_original_palette?
      rules.join("\n")
    end.join("\n")
  end

  def panel_decoration_styles(theme)
    symbols = theme.header_decoration_symbols
    return if symbols.values.all?(&:blank?)

    layout = theme.header_decoration_layout
    elements = layout.fetch(:elements).filter_map do |element|
      symbol = symbols[element.fetch(:role).to_sym]
      next if symbol.blank?

      x, y = element.values_at(:x, :y)
      size = element.fetch(:size)
      attributes = %(data-role="#{element.fetch(:role)}" data-symbol="#{ERB::Util.html_escape(symbol)}" data-size="#{size}")
      if (icon = panel_decoration_icons[symbol])
        %(<g #{attributes} transform="translate(#{x - size / 2.0} #{y - size / 2.0}) rotate(#{element.fetch(:angle)} #{size / 2.0} #{size / 2.0}) scale(#{size / 64.0})">#{icon}</g>)
      else
        %(<text #{attributes} x="#{x}" y="#{y}" font-size="#{size}" transform="rotate(#{element.fetch(:angle)} #{x} #{y})">#{ERB::Util.html_escape(symbol)}</text>)
      end
    end.join
    svg = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{layout.fetch(:view_box)}"><g text-anchor="middle" dominant-baseline="central" font-family="Apple Color Emoji, Segoe UI Emoji, Noto Color Emoji, sans-serif">#{elements}</g></svg>)
    image = "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
    "--app-panel-decoration-image: url(\"#{image}\"); --app-panel-decoration-width: #{layout.fetch(:width)}; --app-panel-decoration-angle: #{layout.fetch(:angle)};"
  end

  def panel_decoration_icons
    @panel_decoration_icons ||= begin
      icons = PANEL_DECORATION_ICONS.keys.index_with do |symbol|
        render(partial: "shared/panel_decoration_icon", locals: { symbol: symbol }).strip
      end
      icons["❄"] = icons.fetch("❄️")
      icons
    end
  end

  def theme_symbol(theme, size:)
    if theme.key == "halloween" && theme.decoration == "🎃"
      image_tag "halloween-pumpkin.svg", alt: "", width: size, height: size
    elsif (icon = panel_decoration_icons[theme.decoration])
      content_tag(:svg, icon.html_safe, viewBox: "0 0 64 64", width: size, height: size,
        fill: "none", aria: { hidden: true }, class: "theme-decoration__symbol")
    else
      tag.span(theme.decoration, class: "theme-decoration__symbol")
    end
  end
end
