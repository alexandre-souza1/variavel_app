require "test_helper"

class ColorThemeTest < ActiveSupport::TestCase
  test "advertisements include both boundaries and stop after November 3 in Brasilia" do
    theme = color_themes(:halloween)
    assert_not_includes ColorTheme.advertised_on(Date.new(2026, 10, 28)), theme
    assert_includes ColorTheme.advertised_on(Date.new(2026, 10, 29)), theme
    assert_includes ColorTheme.advertised_on(Date.new(2026, 11, 3)), theme
    assert_not_includes ColorTheme.advertised_on(Date.new(2026, 11, 4)), theme
    travel_to Time.utc(2026, 11, 4, 2, 59, 59) do
      assert_includes ColorTheme.advertised_on, theme
    end
    travel_to Time.utc(2026, 11, 4, 3, 0, 0) do
      assert_not_includes ColorTheme.advertised_on, theme
    end
  end

  test "promotion needs an ordered complete period and can be turned off" do
    theme = color_themes(:halloween)
    theme.promotion_ends_on = nil
    assert_not theme.valid?
    assert theme.errors[:promotion_ends_on].present?
    theme.promotion_ends_on = theme.promotion_starts_on - 1.day
    assert_not theme.valid?
    theme.update!(promotion_enabled: false, promotion_starts_on: nil, promotion_ends_on: nil)
    assert_not_includes ColorTheme.advertised_on(Date.new(2026, 10, 30)), theme
  end

  test "palette input cannot inject CSS and is normalized before storage" do
    theme = new_theme
    theme.base_color = "#123456; color: red"
    assert_not theme.valid?
    theme.base_color = " #abcdef "
    assert theme.valid?
    assert_equal "#ABCDEF", theme.base_color
  end

  test "new themes work as user preferences and keep their key after renaming" do
    theme = new_theme
    theme.save!
    users(:two).update!(color_theme: theme.key)
    original_key = theme.key
    theme.update!(name: "Natal renovado")
    assert_equal original_key, theme.reload.key
    assert users(:two).reload.valid?
  end

  test "deleting a custom theme resets its users but built in themes remain" do
    theme = new_theme
    theme.save!
    users(:two).update!(color_theme: theme.key)
    theme.destroy!
    assert_equal "blue_teal", users(:two).reload.color_theme
    assert_not color_themes(:halloween).destroy
    assert ColorTheme.exists?(key: "halloween")
  end

  test "built in names cannot be used to replace existing themes" do
    theme = new_theme
    theme.name = "Blue Teal"
    assert_not theme.valid?
    assert theme.errors[:name].present?
  end

  test "imported themes keep their palettes and seed reruns preserve administrator changes" do
    theme = color_themes(:earthy_forest_hues)
    assert_equal %w[#DAD7CD #A3B18A #588157 #3A5A40 #344E41], theme.palette
    assert theme.preserve_original_palette?
    theme.update!(name: "Floresta", promotion_text: "Experimente a floresta")
    assert_no_difference "ColorTheme.count" do
      ColorTheme.ensure_builtin_themes!
    end
    assert_equal "Floresta", theme.reload.name
    assert theme.preserve_original_palette?
    assert_not theme.promotion_enabled?
  end

  test "only palette changes switch an imported theme to generated colors" do
    theme = color_themes(:blue_teal)
    users(:two).update!(color_theme: theme.key)
    theme.update!(name: "Azul", promotion_enabled: true,
      promotion_starts_on: Date.new(2026, 10, 29), promotion_ends_on: Date.new(2026, 11, 3))
    assert theme.reload.preserve_original_palette?
    theme.update!(primary_color: "#123456")
    assert_not theme.reload.preserve_original_palette?
    assert_equal "blue_teal", users(:two).reload.color_theme
    assert_equal "#123456", theme.css_variables(:light).fetch("app-primary")
  end

  test "optional fifth color is validated and can be cleared" do
    theme = color_themes(:earthy_forest_hues)
    theme.extra_color = "not a color"
    assert_not theme.valid?
    theme.update!(extra_color: "")
    assert_equal 4, theme.palette.size
    assert_nil theme.extra_color
  end

  test "very dark green bases produce tinted graphite layers instead of an almost black page" do
    theme = ColorTheme.new(name: "Bosque", base_color: "#09251C", primary_color: "#A55704",
      accent_color: "#F3D2AF", highlight_color: "#F8EADC")
    colors = theme.css_variables(:dark)
    red, green, blue = channels(colors.fetch("app-dark-page"))
    assert green >= 45, "dark background should retain visible color"
    assert green > red
    assert blue > red
    assert green - red < 20, "the page should have a subtle forest tint rather than a dominant green fill"
    assert luminance(colors.fetch("app-dark-input")) < luminance(colors.fetch("app-dark-page"))
    assert luminance(colors.fetch("app-dark-page")) < luminance(colors.fetch("app-dark-surface"))
    assert luminance(colors.fetch("app-dark-surface")) < luminance(colors.fetch("app-dark-elevated"))
  end

  test "dark themes retain the orange primary in details and links instead of replacing it with cream" do
    theme = ColorTheme.new(base_color: "#09251C", primary_color: "#A55704",
      accent_color: "#F3D2AF", highlight_color: "#F8EADC")
    colors = theme.css_variables(:dark)
    red, green, blue = channels(colors.fetch("app-primary"))
    assert red > green
    assert green > blue
    assert blue < 64, "orange accents should retain their saturation"
    assert_not_equal colors.fetch("app-soft"), colors.fetch("app-primary")
    assert_equal colors.fetch("app-primary"), colors.fetch("bs-primary-text-emphasis")
    assert_equal colors.fetch("app-primary"), colors.fetch("bs-link-color")
    assert_equal colors.fetch("app-primary-rgb"), colors.fetch("bs-link-color-rgb")
    assert_equal colors.fetch("app-soft"), colors.fetch("bs-link-hover-color")
    assert_equal "#A55704", colors.fetch("app-button-solid")
  end

  test "neutral dark bases borrow a tint from another color in the palette" do
    theme = ColorTheme.new(base_color: "#010101", primary_color: "#202020", accent_color: "#80426E", highlight_color: "#F3D2AF")
    red, green, blue = channels(theme.css_variables(:dark).fetch("app-dark-page"))
    assert red > green
    assert blue > green
    assert [red, green, blue].max >= 45
  end

  test "dark text and accents remain readable across every generated background layer" do
    [
      %w[#09251C #A55704 #F3D2AF #F8EADC],
      %w[#000000 #000000 #000000 #000000],
      %w[#FFFFFF #FFFFFF #FFFFFF #FFFFFF],
      %w[#FF0000 #FFFF00 #FFFFFF #000000],
      %w[#000010 #102060 #80B0FF #F0F8FF]
    ].each do |palette|
      theme = ColorTheme.new(ColorTheme::COLOR_FIELDS.zip(palette).to_h)
      colors = theme.css_variables(:dark)
      backgrounds = %w[app-dark-page app-dark-surface app-dark-elevated app-dark-input app-dark-deep app-dark-hover app-strong]
      %w[app-dark-text app-dark-muted app-primary app-soft].each do |foreground|
        backgrounds.each do |background|
          bright, dark = [luminance(colors.fetch(foreground)), luminance(colors.fetch(background))].sort.reverse
          assert (bright + 0.05) / (dark + 0.05) >= 4.5, "#{palette}: #{foreground} on #{background} needs 4.5:1 contrast"
        end
      end
      assert channels(colors.fetch("app-dark-page")).max >= 45
    end
  end

  private

  def channels(hex)
    hex.delete_prefix("#").scan(/../).map { |value| value.to_i(16) }
  end

  def luminance(hex)
    channels(hex).map do |value|
      normalized = value / 255.0
      normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055)**2.4
    end.zip([0.2126, 0.7152, 0.0722]).sum { |value, weight| value * weight }
  end

  def new_theme
    ColorTheme.new(name: "Natal", base_color: "#164A38", primary_color: "#9B243A",
      accent_color: "#D9AC50", highlight_color: "#F7ECD8", decoration: "🎄")
  end
end
