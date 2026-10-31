class DailySummaryDispatchJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current
    date = now.in_time_zone(DailySummary::TIME_ZONE).to_date
    return if now < DailySummary.delivery_time(date)

    User.active.where(daily_summary_enabled: true).where("daily_summary_next_run_at <= ?", now).find_each do |user|
      summary = user.daily_summaries.create_or_find_by!(summary_date: date) do |record|
        record.next_attempt_at = now
      end
      reserved = summary.with_lock do
        next false if summary.delivered? || summary.next_attempt_at > now

        summary.update!(status: :queued, processing_token: nil, next_attempt_at: now + DailySummary::LEASE_DURATION)
        true
      end
      next unless reserved

      job = DailySummaryJob.perform_later(summary.id)
      raise ActiveJob::EnqueueError, "Resumo não enfileirado" unless job
    rescue StandardError => error
      Rails.logger.error("[DailySummaryDispatch] user_id=#{user.id} error_class=#{error.class.name}")
      # The reservation expires, so the scheduler retries even after a Redis outage.
    end
  end
end
