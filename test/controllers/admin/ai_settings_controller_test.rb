require "test_helper"

class Admin::AiSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    AiSetting.current.update!(primary_model: "gemini-3.6-flash", meeting_audio_max_minutes: 15, model_limits: {})
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

    assert_redirected_to edit_admin_ai_setting_url(tab: "settings")
    assert_equal "gemini-3.1-flash-lite", AiSetting.current.primary_model
    assert_equal 30, AiSetting.current.meeting_audio_max_minutes
  end

  test "administrador vê os quatro modelos e salva limites sem confundir branco com zero" do
    users(:one).update!(role: :admin)
    patch admin_ai_setting_url, params: { ai_setting: { model_limits: {
      "gemini-3.6-flash" => { rpm: "10", tpm: "100000", rpd: "100" },
      "gemini-3.1-flash-lite" => { rpm: "0", tpm: "", rpd: "" }
    } } }
    assert_redirected_to edit_admin_ai_setting_url(tab: "settings")
    limits = AiSetting.current.model_limits
    assert_equal 10, limits.dig("gemini-3.6-flash", "rpm")
    assert_equal 0, limits.dig("gemini-3.1-flash-lite", "rpm")
    assert_nil limits.dig("gemini-3.1-flash-lite", "tpm")

    get edit_admin_ai_setting_url(tab: "models")
    assert_response :success
    assert_select ".ai-usage-card", count: 4
    assert_select ".ai-usage-card[data-model='gemini-3.6-flash'] .ai-usage-card__primary", text: "Prioritário"
    assert_select ".ai-model-limits input[type='number']", count: 0
    get edit_admin_ai_setting_url(tab: "settings")
    assert_select ".ai-model-limits input[type='number']", count: 12
    assert_select "a[href=?]", "https://aistudio.google.com/usage?tab=rate-limit"
  end

  test "invalid quota values render errors and preserve the stored settings" do
    users(:one).update!(role: :admin)
    AiSetting.current.update!(model_limits: { "gemini-3.6-flash" => { "rpm" => 10 } })
    patch admin_ai_setting_url, params: { ai_setting: { model_limits: { "gemini-3.6-flash" => { rpm: "-1" } } } }
    assert_response :unprocessable_entity
    assert_select ".alert-danger", text: /números inteiros/
    assert_equal 10, AiSetting.current.model_limits.dig("gemini-3.6-flash", "rpm")
  end

  test "regular users cannot change usage limits" do
    patch admin_ai_setting_url, params: { ai_setting: { model_limits: { "gemini-3.6-flash" => { rpm: "999" } } } }
    assert_redirected_to root_url
    assert_nil AiSetting.current.model_limits.dig("gemini-3.6-flash", "rpm")
  end

  test "tabs show one section at a time and reject unknown tab names" do
    users(:one).update!(role: :admin)
    get edit_admin_ai_setting_url
    assert_response :success
    assert_select ".ai-settings-tabs__link", count: 4
    assert_select "#ai-tab-overview"
    assert_select ".ai-usage-card", count: 0
    assert_select ".ai-model-limits", count: 0
    get edit_admin_ai_setting_url(tab: "../../users")
    assert_response :success
    assert_select "#ai-tab-overview"
  end

  test "user statistics contain metadata and never read or expose private conversations" do
    users(:one).update!(role: :admin)
    users(:two).update!(name: "Bruno")
    AiApiRequest.create!(user: users(:two), model: "gemini-3.6-flash", feature: "assistant",
      requested_at: Time.current, http_status: 200, duration_ms: 100, input_tokens: 80, output_tokens: 20,
      credential_fingerprint: AiApiRequest.current_credential_fingerprint)
    conversation = AiConversation.create!(user: users(:two))
    conversation.ai_messages.create!(role: "user", content: "PERGUNTA_PRIVADA_98271")
    sql = []
    ActiveSupport::Notifications.subscribed(->(_name, _start, _finish, _id, payload) { sql << payload[:sql] }, "sql.active_record") do
      get edit_admin_ai_setting_url(tab: "users")
    end
    assert_response :success
    assert_select ".ai-report-users__table", text: /Bruno/
    refute_includes response.body, "PERGUNTA_PRIVADA_98271"
    refute sql.any? { |query| query.match?(/\bai_messages\b|\bai_conversations\b/) }, "Usage reports must not read conversations"
  end

  test "user statistics remain restricted to administrators" do
    get edit_admin_ai_setting_url(tab: "users")
    assert_redirected_to root_url
  end
end
