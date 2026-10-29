require "test_helper"
require "minitest/mock"

class Admin::ColorThemeGenerationTest < ActionDispatch::IntegrationTest
  test "AI creation is exposed in the admin index and opens the generator" do
    get admin_color_themes_path
    assert_select "a[href=?]", new_admin_color_theme_path(ai: 1), text: /Criar com IA/
    get new_admin_color_theme_path(ai: 1)
    assert_select '[data-color-theme-generator-auto-open-value="true"]'
    assert_select "dialog.color-theme-ai"
    assert_select ".color-theme-form .color-theme-ai", count: 0
    assert_select "textarea#color-theme-ai-colors"
    assert_select "[data-preview-mode=light]"
    assert_select "[data-preview-mode=dark]"
  end

  test "ordinary users and visitors cannot invoke generation" do
    GeminiThemeService.stub(:new, ->(**) { flunk "Unauthorized request reached the generator" }) do
      users(:one).update!(role: :user)
      post generate_admin_color_themes_path, params: { colors: "#522D60" }, as: :json
      assert_redirected_to root_path
      sign_out users(:one)
      post generate_admin_color_themes_path, params: { colors: "#522D60" }, as: :json
      assert_response :unauthorized
    end
  end

  test "generation uses the authenticated administrator and returns an unsaved draft" do
    draft = { "name" => "Tema sugerido", "base_color" => "#164A38", "primary_color" => "#9B243A",
      "accent_color" => "#D9AC50", "highlight_color" => "#F7ECD8", "extra_color" => nil,
      "description" => "Uma paleta festiva", "decoration" => "🌿", "promotion_text" => "Experimente o tema" }
    generator = Object.new
    generator.define_singleton_method(:call) { draft }
    factory = lambda do |colors:, user:|
      assert_equal "#164A38 #9B243A #D9AC50 #F7ECD8", colors
      assert_equal users(:one).id, user.id
      generator
    end
    assert_no_difference "ColorTheme.count" do
      GeminiThemeService.stub(:new, factory) do
        post generate_admin_color_themes_path, params: { colors: "#164A38 #9B243A #D9AC50 #F7ECD8", user_id: users(:two).id }, as: :json
      end
    end
    assert_response :success
    assert_equal draft, response.parsed_body.fetch("theme")
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_difference "ColorTheme.count", 1 do
      post admin_color_themes_path, params: { color_theme: draft }
    end
    assert_redirected_to admin_color_themes_path
    assert_not ColorTheme.find_by!(name: "Tema sugerido").promotion_enabled?
  end

  test "invalid colors never call Gemini and return an actionable error" do
    Faraday.stub(:post, ->(*) { flunk "Invalid input must not call Gemini" }) do
      post generate_admin_color_themes_path, params: { colors: "not a hex" }, as: :json
    end
    assert_response :unprocessable_entity
    assert_match(/HEX/, response.parsed_body.fetch("error"))
  end

  test "quota failures return a retryable error without saving a theme" do
    generator = Object.new
    generator.define_singleton_method(:call) { raise GeminiThemeService::Unavailable.new(:quota) }
    assert_no_difference "ColorTheme.count" do
      GeminiThemeService.stub(:new, ->(**) { generator }) do
        post generate_admin_color_themes_path, params: { colors: "#522D60" }, as: :json
      end
    end
    assert_response :too_many_requests
    assert_match(/limite/, response.parsed_body.fetch("error"))
  end
end
