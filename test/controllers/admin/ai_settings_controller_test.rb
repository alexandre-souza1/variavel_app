require "test_helper"

class Admin::AiSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    users(:one).update!(role: :user)
    sign_in users(:one)
  end

  test "bloqueia configurações de IA para não administradores" do
    get edit_admin_ai_setting_url

    assert_redirected_to root_url
  end

  test "administrador consegue atualizar o modelo e o limite da gravação" do
    users(:one).update!(role: :admin)

    patch admin_ai_setting_url, params: {
      ai_setting: {
        primary_model: "gemini-3.1-flash-lite",
        meeting_audio_max_minutes: 30
      }
    }

    assert_redirected_to edit_admin_ai_setting_url
    assert_equal "gemini-3.1-flash-lite", AiSetting.current.primary_model
    assert_equal 30, AiSetting.current.meeting_audio_max_minutes
  end
end
