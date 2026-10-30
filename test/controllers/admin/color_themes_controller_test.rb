require "test_helper"

class Admin::ColorThemesControllerTest < ActionDispatch::IntegrationTest
  test "all original themes appear in administration without automatic promotion" do
    get admin_color_themes_path
    assert_response :success
    assert_select ".color-theme-card", count: 7
    User::COLOR_THEMES.each_key { |name| assert_select ".color-theme-card h2", text: /#{Regexp.escape(name)}/ }
    assert_select ".color-theme-card .badge", count: 1, text: "Sazonal"
    assert_not_includes response.body, "Sem aviso"
    assert_not_includes response.body, "sem divulgação programada"
    get edit_admin_color_theme_path(color_themes(:earthy_forest_hues))
    assert_response :success
    assert_select "input#color_theme_extra_color[value=?]", "#344E41"
    patch admin_color_theme_path(color_themes(:blue_teal)), params: {
      color_theme: { name: "Azul original", promotion_enabled: true,
        promotion_starts_on: "2026-10-29", promotion_ends_on: "2026-11-03" }
    }
    assert_redirected_to admin_color_themes_path
    assert color_themes(:blue_teal).reload.preserve_original_palette?
    travel_to Time.zone.local(2026, 10, 30) do
      get root_path, params: { force_home: true }
      assert_select 'button.theme-promo[data-theme-color-param=blue_teal]'
      assert_select '#navbarColorTheme option[value=blue_teal]', text: "AZUL ORIGINAL"
      assert_not_includes response.body, 'html[data-bs-theme="light"][data-color-theme="blue_teal"]'
    end
  end

  test "only administrators can manage themes" do
    users(:one).update!(role: :user)
    theme = color_themes(:halloween)
    get admin_color_themes_path
    assert_redirected_to root_path
    get new_admin_color_theme_path
    assert_redirected_to root_path
    get edit_admin_color_theme_path(theme)
    assert_redirected_to root_path
    assert_no_difference "ColorTheme.count" do
      post admin_color_themes_path, params: { color_theme: theme_params }
      delete admin_color_theme_path(theme)
    end
    patch admin_color_theme_path(theme), params: { color_theme: { name: "Alterado" } }
    assert_redirected_to root_path
    assert_equal "Halloween", theme.reload.name
  end

  test "admin creates and edits a theme that is available in selectors and saved preferences" do
    get new_admin_color_theme_path
    assert_response :success
    assert_select "input[name=?]", "color_theme[base_color]"
    assert_select "input[name=?]", "color_theme[header_companion]"
    assert_select "[data-preview-panel-header]", count: 2
    assert_difference "ColorTheme.count", 1 do
      post admin_color_themes_path, params: { color_theme: theme_params.merge(key: "injected_key", header_companion: "❄️", header_detail: "⭐") }
    end
    assert_redirected_to admin_color_themes_path
    theme = ColorTheme.find_by!(name: "Natal")
    assert_equal "natal", theme.key
    assert_equal({ primary: "🎄", secondary: "❄️", detail: "⭐" }, theme.header_decoration_symbols)
    patch admin_color_theme_path(theme), params: { color_theme: { name: "Natal especial", key: "changed_key" } }
    assert_redirected_to admin_color_themes_path
    assert_equal "natal", theme.reload.key
    get root_path, params: { force_home: true }
    assert_select "#navbarColorTheme option[value=natal]", text: "NATAL ESPECIAL"
    assert_includes response.body, 'data-color-themes='
    assert_includes response.body, 'data-color-theme="natal"'
    get admin_users_path(edit_user_id: users(:one).id)
    assert_select "#user_color_theme_natal"
    patch admin_user_path(users(:one)), params: { user: { color_theme: "natal" } }
    assert_response :success
    assert_equal "natal", users(:one).reload.color_theme
  end

  test "scheduled invitations appear only in their period and use reusable theme actions" do
    travel_to Time.zone.local(2026, 11, 3, 23, 59) do
      get root_path, params: { force_home: true }
      assert_select 'button.theme-promo[data-theme-color-param=halloween]', text: /Experimente o Halloween/
    end
    travel_to Time.zone.local(2026, 11, 4, 0, 0) do
      get root_path, params: { force_home: true }
      assert_select 'button.theme-promo[data-theme-color-param=halloween]', count: 0
      assert_select '#navbarColorTheme option[value=halloween]', count: 1
    end
    travel_to Time.zone.local(2026, 10, 28, 23, 59) do
      get root_path, params: { force_home: true }
      assert_select '.theme-promo', count: 0
    end
  end

  test "invalid colors and reversed dates render errors without saving" do
    assert_no_difference "ColorTheme.count" do
      post admin_color_themes_path, params: { color_theme: theme_params.merge(
        base_color: "#bad; background: red", promotion_enabled: true,
        promotion_starts_on: "2026-12-25", promotion_ends_on: "2026-12-01") }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]"
  end

  test "admin can remove custom themes but cannot remove Halloween" do
    theme = ColorTheme.create!(theme_params)
    users(:two).update!(color_theme: theme.key)
    assert_difference "ColorTheme.count", -1 do
      delete admin_color_theme_path(theme)
    end
    assert_redirected_to admin_color_themes_path
    assert_equal "blue_teal", users(:two).reload.color_theme
    assert_no_difference "ColorTheme.count" do
      delete admin_color_theme_path(color_themes(:halloween))
    end
    assert_redirected_to admin_color_themes_path
  end

  private

  def theme_params
    { name: "Natal", description: "Cores natalinas", base_color: "#164A38", primary_color: "#9B243A",
      accent_color: "#D9AC50", highlight_color: "#F7ECD8", decoration: "🎄" }
  end
end
