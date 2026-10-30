class ColorTheme < ApplicationRecord
  COLOR_FIELDS = %i[base_color primary_color accent_color highlight_color].freeze
  PALETTE_FIELDS = (COLOR_FIELDS + [:extra_color]).freeze
  HEADER_DECORATION_FIELDS = %i[header_symbol header_companion header_detail].freeze
  # A mesma receita posiciona os símbolos na interface e na prévia do editor.
  HEADER_DECORATION_LAYOUTS = {
    single: { view_box: "0 0 64 64", width: "2.5rem", angle: "-12deg",
      elements: [{ role: "primary", x: 32, y: 34, size: 48, angle: 0 }] },
    corner: { view_box: "0 0 128 64", width: "6rem", angle: "0deg",
      elements: [
        { role: "secondary", x: 55, y: 26, size: 34, angle: -12 },
        { role: "primary", x: 87, y: 36, size: 46, angle: 8 },
        { role: "detail", x: 21, y: 14, size: 11, angle: -8 },
        { role: "detail", x: 60, y: 51, size: 8, angle: 16 }
      ] }
  }.freeze
  # Compartilhada com a prévia: superfícies grafite recebem a matiz da paleta,
  # sem multiplicar a escuridão de uma cor base que já pode ser quase preta.
  DARK_PALETTE_RECIPE = {
    tint_peak: 112, saturation_floor: 0.12, hover_mix: 0.12, border_mix: 0.28, primary_boost: 1.12,
    surfaces: {
      page: ["#242824", 0.12], surface: ["#2D322E", 0.14], elevated: ["#373E38", 0.16],
      input: ["#1C201D", 0.10], deep: ["#181C19", 0.08], bar: ["#202B25", 0.40]
    }.freeze
  }.freeze
  BUILTIN_PALETTES = {
    "blue_teal" => ["Azul equilibrado com detalhes em azul-petróleo.", %w[#3368A0 #66A3BF #C8DFDB #F2EFE7], "#3368A0"],
    "sage_teal" => ["Verde-azulado suave e corporativo.", %w[#2D9596 #265073 #9AD0C2 #ECF4D6], "#265073"],
    "retro_orange" => ["Creme, verde e laranja com personalidade.", %w[#527853 #F9E8D9 #F7B787 #EE7214], "#527853"],
    "black_mint" => ["Base escura com verdes menta marcantes.", %w[#092328 #12544F #2A835F #8BBB92], "#2A835F"],
    "white_tea_sage" => ["Tons claros e naturais de chá branco e sálvia.", %w[#8B9A6E #F7F2EB #EAE2D6 #EEEEEE], "#8B9A6E"],
    "earthy_forest_hues" => ["Tons terrosos e verdes inspirados na floresta.", %w[#DAD7CD #A3B18A #588157 #3A5A40 #344E41], "#588157"],
    "halloween" => ["Roxos, pêssego e dourado com abóboras e pequenos sustos.", %w[#522D60 #80426E #F2A67B #FFD38B], "#522D60"]
  }.freeze

  before_validation :normalize_palette
  before_validation :assign_key, on: :create
  before_update :recalculate_palette_when_colors_change
  before_destroy :preserve_builtin_theme
  before_destroy :reset_user_preferences

  attr_readonly :key
  store_accessor :header_decoration, *HEADER_DECORATION_FIELDS

  validates :name, presence: true, length: { maximum: 40 }, uniqueness: { case_sensitive: false }
  validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:_[a-z0-9]+)*\z/ }
  validates(*COLOR_FIELDS, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "deve ser uma cor hexadecimal, como #522D60" })
  validates :extra_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "deve ser uma cor hexadecimal, como #522D60" }, allow_blank: true
  validates :description, length: { maximum: 160 }
  validates :decoration, length: { maximum: 16 }
  validates(*HEADER_DECORATION_FIELDS, length: { maximum: 16 })
  validates :promotion_text, length: { maximum: 64 }
  validates :promotion_starts_on, :promotion_ends_on, presence: true, if: :promotion_enabled?
  validate :promotion_period_is_ordered
  validate :key_is_available
  validate :header_decoration_uses_single_symbols

  scope :advertised_on, ->(date = Date.current) {
    where(promotion_enabled: true).where("promotion_starts_on <= ? AND promotion_ends_on >= ?", date, date)
  }

  def palette
    PALETTE_FIELDS.filter_map { |field| public_send(field).presence }
  end

  def self.ensure_builtin_themes!
    transaction do
      User::COLOR_THEMES.except("Halloween").each do |name, key|
        description, colors = BUILTIN_PALETTES.fetch(key)
        find_or_create_by!(key: key) do |theme|
          theme.assign_attributes(name: name, description: description,
            base_color: colors[0], primary_color: colors[1], accent_color: colors[2], highlight_color: colors[3],
            extra_color: colors[4], preserve_original_palette: true, promotion_enabled: false)
        end
      end
    end
  end

  def invitation
    promotion_text.presence || "Experimente #{name}"
  end

  def header_decoration_symbols
    { primary: header_symbol.presence || decoration.presence,
      secondary: header_companion.presence, detail: header_detail.presence }
  end

  def header_decoration_layout
    symbols = header_decoration_symbols
    HEADER_DECORATION_LAYOUTS.fetch(symbols[:secondary] || symbols[:detail] ? :corner : :single)
  end

  # Quatro cores geram as superfícies dos dois modos. Textos e botões recebem
  # contraste suficiente mesmo quando a paleta cadastrada é muito clara.
  def css_variables(mode)
    strong = readable_on_white(base_color)
    primary = readable_on_white(primary_color)
    common = { "app-strong" => strong, "app-button-solid" => primary }

    if mode == :light
      common.merge(
        "app-primary" => primary, "app-primary-rgb" => rgb(primary).join(", "),
        "app-soft" => accent_color, "app-page-bg" => blend(highlight_color, "#FFFFFF", 0.88),
        "app-surface" => blend(highlight_color, "#FFFFFF", 0.97),
        "app-secondary-bg" => blend(highlight_color, "#FFFFFF", 0.12),
        "app-tertiary-bg" => blend(highlight_color, "#FFFFFF", 0.93),
        "app-muted" => readable_on_white(blend(strong, "#FFFFFF", 0.2))
      )
    else
      surfaces = dark_surfaces
      backdrop = surfaces.values.max_by { |color| luminance(color) }
      primary = readable_primary_on_dark(backdrop)
      soft = readable_on_dark(accent_color, backdrop)
      common.merge(
        "app-strong" => surfaces.fetch(:bar),
        "app-primary" => primary, "app-primary-rgb" => rgb(primary).join(", "),
        "app-soft" => soft,
        "bs-primary-text-emphasis" => primary,
        "bs-link-color" => primary, "bs-link-color-rgb" => rgb(primary).join(", "),
        "bs-link-hover-color" => soft, "bs-link-hover-color-rgb" => rgb(soft).join(", "),
        "app-dark-page" => surfaces.fetch(:page), "app-dark-surface" => surfaces.fetch(:surface),
        "app-dark-elevated" => surfaces.fetch(:elevated), "app-dark-input" => surfaces.fetch(:input),
        "app-dark-hover" => surfaces.fetch(:hover), "app-dark-deep" => surfaces.fetch(:deep),
        "app-dark-border" => blend(surfaces.fetch(:elevated), readable_on_dark(primary_color, backdrop), DARK_PALETTE_RECIPE.fetch(:border_mix)),
        "app-dark-text" => readable_on_dark(blend(highlight_color, "#FFFFFF", 0.9), backdrop),
        "app-dark-muted" => readable_on_dark(blend(highlight_color, "#FFFFFF", 0.55), backdrop)
      )
    end
  end

  private

  def normalize_palette
    COLOR_FIELDS.each { |field| public_send("#{field}=", public_send(field).to_s.strip.upcase) }
    self.extra_color = extra_color.to_s.strip.upcase.presence
    self.name = name.to_s.strip
    self.decoration = decoration.to_s.strip
    HEADER_DECORATION_FIELDS.each do |field|
      public_send("#{field}=", public_send(field).to_s.strip.presence)
    end
  end

  def header_decoration_uses_single_symbols
    HEADER_DECORATION_FIELDS.each do |field|
      errors.add(field, "deve conter apenas um símbolo") if public_send(field).to_s.scan(/\X/).size > 1
    end
  end

  def assign_key
    self.key = name.to_s.parameterize(separator: "_") if key.blank?
  end

  def key_is_available
    if new_record? && !preserve_original_palette? && key != "halloween" && User::COLOR_THEMES.values.include?(key)
      errors.add(:name, "já é utilizado por um tema padrão")
    end
  end

  def recalculate_palette_when_colors_change
    self.preserve_original_palette = false if PALETTE_FIELDS.any? { |field| will_save_change_to_attribute?(field) }
  end

  def promotion_period_is_ordered
    if promotion_starts_on && promotion_ends_on && promotion_ends_on < promotion_starts_on
      errors.add(:promotion_ends_on, "deve ser igual ou posterior ao início")
    end
  end

  def preserve_builtin_theme
    return unless User::COLOR_THEMES.values.include?(key)

    errors.add(:base, "Este tema faz parte do aplicativo. Você pode editar ou desativar seu aviso.")
    throw :abort
  end

  def reset_user_preferences
    User.where(color_theme: key).update_all(color_theme: "blue_teal", updated_at: Time.current)
  end

  def rgb(color)
    color.delete_prefix("#").scan(/../).map { |channel| channel.to_i(16) }
  end

  def dark_surfaces
    source = palette.find do |color|
      channels = rgb(color)
      channels.max.positive? && (channels.max - channels.min).fdiv(channels.max) >= DARK_PALETTE_RECIPE.fetch(:saturation_floor)
    end || base_color
    channels = rgb(source)
    peak = DARK_PALETTE_RECIPE.fetch(:tint_peak)
    tint = if channels.max.zero?
      "#" + peak.to_s(16).rjust(2, "0") * 3
    else
      "#" + channels.map { |channel| (channel.fdiv(channels.max) * peak).round.to_s(16).rjust(2, "0") }.join
    end
    surfaces = DARK_PALETTE_RECIPE.fetch(:surfaces).transform_values { |neutral, amount| blend(neutral, tint, amount) }
    surfaces[:hover] = blend(surfaces.fetch(:elevated), tint, DARK_PALETTE_RECIPE.fetch(:hover_mix))
    surfaces
  end

  def blend(color, other, amount)
    channels = rgb(color).zip(rgb(other)).map { |a, b| (a * (1 - amount) + b * amount).round }
    "#" + channels.map { |channel| channel.to_s(16).rjust(2, "0") }.join.upcase
  end

  def readable_on_white(color)
    candidate = color
    loop do
      return candidate if 1.05 / (luminance(candidate) + 0.05) >= 4.5

      candidate = blend(candidate, "#000000", 0.1)
    end
  end

  def readable_on_dark(color, background)
    candidate = color
    loop do
      return candidate if (luminance(candidate) + 0.05) / (luminance(background) + 0.05) >= 4.5

      candidate = blend(candidate, "#FFFFFF", 0.1)
    end
  end

  # Primeiro aumenta a luminosidade preservando a proporção dos canais.
  # Misturar com branco desde o início apagaria o laranja (ou outra cor principal).
  def readable_primary_on_dark(background)
    channels = rgb(primary_color)
    original_peak = channels.max
    peak = original_peak
    candidate = primary_color
    while peak.positive? && peak < 255 && (luminance(candidate) + 0.05) / (luminance(background) + 0.05) < 4.5
      peak = [(peak * DARK_PALETTE_RECIPE.fetch(:primary_boost)).ceil, 255].min
      candidate = "#" + channels.map { |channel| (channel.fdiv(original_peak) * peak).round.to_s(16).rjust(2, "0") }.join.upcase
    end
    readable_on_dark(candidate, background)
  end

  def luminance(color)
    rgb(color).map { |channel|
      value = channel / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    }.zip([0.2126, 0.7152, 0.0722]).sum { |channel, weight| channel * weight }
  end
end
