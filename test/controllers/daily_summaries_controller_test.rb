require "test_helper"

class DailySummariesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @summary = users(:one).daily_summaries.create!(summary_date: Date.current, status: :delivered,
      content: "**Agenda**\n- Conferir tarefas\n<script>alert('unsafe')</script>", sources: [],
      delivered_at: Time.current, next_attempt_at: Time.current)
  end

  test "recipient can read the full summary with private caching and escaped model output" do
    get daily_summary_path(@summary)
    assert_response :success
    assert_equal %w[no-store private], response.headers["Cache-Control"].split(", ").sort
    assert_select ".daily-summary-content", text: /Conferir tarefas/
    assert_select ".daily-summary-content script", count: 0
  end

  test "another account including an admin cannot read a private summary" do
    sign_in users(:two)
    users(:two).update!(role: :admin)
    get daily_summary_path(@summary)
    assert_response :not_found
  end

  test "unfinished summaries are not exposed" do
    @summary.update!(status: :pending)
    get daily_summary_path(@summary)
    assert_response :not_found
  end

  test "reading the notification opens the stored summary instead of calling Gemini again" do
    notification = users(:one).notifications.create!(kind: "daily_summary", title: "Resumo do dia",
      notifiable: @summary, action_url: daily_summary_path(@summary), action_text: "Ler resumo")

    patch read_notification_path(notification)
    assert_redirected_to daily_summary_path(@summary)
    assert notification.reload.read?
  end
end
