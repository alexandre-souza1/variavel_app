class DailySummaryJob < ApplicationJob
  queue_as :default

  def perform(summary_id)
    summary = DailySummary.find_by(id: summary_id)
    return unless summary

    token = SecureRandom.uuid
    claimed = summary.with_lock do
      next false unless summary.eligible? && !summary.delivered?
      next false if summary.pending? && summary.next_attempt_at > Time.current
      next false if summary.processing? && summary.processing_started_at.present? && summary.processing_started_at > DailySummary::LEASE_DURATION.ago

      summary.update!(status: :processing, processing_token: token, processing_started_at: Time.current,
                      attempts: summary.attempts + 1, next_attempt_at: Time.current + DailySummary::LEASE_DURATION)
      true
    end
    return unless claimed

    audience = [summary.user.role, summary.user.sector]
    answer = AiAssistant::DailySummaryGenerator.new(user: summary.user).call

    summary.with_lock do
      next unless summary.processing_token == token
      user = User.lock.find(summary.user_id)
      summary.user = user
      next unless summary.eligible?

      if audience != [user.role, user.sector]
        summary.update!(status: :pending, processing_token: nil, next_attempt_at: Time.current)
        next
      end

      Notification.create!(user: user, notifiable: summary, kind: "daily_summary",
        title: "Resumo do dia · #{I18n.l(summary.summary_date)}",
        body: "Seu resumo com agenda, prioridades e alertas já está disponível.",
        action_text: "Ler resumo", action_url: Rails.application.routes.url_helpers.daily_summary_path(summary))
      summary.update!(status: :delivered, content: answer.fetch(:content), sources: answer.fetch(:sources),
                      delivered_at: Time.current, processing_token: nil, last_error: nil)
      user.update!(daily_summary_next_run_at: DailySummary.next_delivery)
    end
  rescue StandardError => error
    Rails.logger.error("[DailySummary] summary_id=#{summary_id} error_class=#{error.class.name}")
    summary&.with_lock do
      next unless summary.processing_token == token && !summary.delivered?

      delay = [2**[summary.attempts, 6].min, 60].min.minutes
      reason = error.is_a?(AiAssistant::Responder::Unavailable) ? error.reason.to_s : "internal"
      summary.update!(status: :pending, processing_token: nil, last_error: reason,
                      next_attempt_at: Time.current + delay)
    end
  end
end
