class MeetingMinuteGenerationJob < ApplicationJob
  queue_as :default

  retry_on Faraday::TimeoutError, Faraday::ConnectionFailed,
    wait: :exponentially_longer, attempts: 3 do |job, error|
      job.mark_failed(job.arguments.first, error)
    end
  retry_on GeminiMeetingService::TemporaryError,
    wait: :exponentially_longer, attempts: 5 do |job, error|
      job.mark_failed(job.arguments.first, error)
    end
  discard_on ActiveRecord::RecordNotFound
  after_discard do |job, error|
    job.mark_failed(job.arguments.first, error)
  end

  def perform(meeting_id)
    meeting = MeetingMinute.find(meeting_id)

    # A ata só pode ser assumida uma vez. Isso evita processamento duplicado
    # caso o formulário seja reenviado ou o job seja enfileirado novamente.
    claimed = MeetingMinute
      .where(id: meeting.id, status: MeetingMinute.statuses[:queued])
      .update_all(status: MeetingMinute.statuses[:processing], updated_at: Time.current)

    return unless claimed == 1

    result = GeminiMeetingService.new(meeting.reload).call

    meeting.update!(
      status: :completed,
      transcript: result["transcript"],
      summary: result["summary"],
      original_summary: result["summary"],
      decisions: Array(result["decisions"]),
      pending_items: Array(result["pending_items"]),
      tasks_suggestions: Array(result["tasks"]),
      original_decisions: Array(result["decisions"]),
      original_pending_items: Array(result["pending_items"])
    )

    # A ata já foi persistida com sucesso. O áudio original não é mais
    # necessário para o processamento e pode ser removido do storage remoto.
    meeting.audio.purge_later if meeting.audio.attached?

    notify_user(meeting, "Ata gerada", "A ata da reunião está pronta para revisão.")
  rescue StandardError => e
    if e.is_a?(Faraday::TimeoutError) || e.is_a?(Faraday::ConnectionFailed) ||
        e.is_a?(GeminiMeetingService::TemporaryError)
      # O retry precisa conseguir assumir novamente o meeting. O áudio continua
      # anexado ao registro e não é descartado quando o provedor está indisponível.
      MeetingMinute.where(id: meeting_id, status: MeetingMinute.statuses[:processing]).update_all(
        status: MeetingMinute.statuses[:queued],
        error_message: e.message,
        updated_at: Time.current
      )
      raise
    end

    mark_failed(meeting_id, e)
  end

  def mark_failed(meeting_id, error)
    Rails.logger.error("Falha ao gerar ata #{meeting_id}: #{error.class}: #{error.message}")
    MeetingMinute.where(id: meeting_id).update_all(
      status: MeetingMinute.statuses[:failed],
      error_message: error.message,
      updated_at: Time.current
    )
    notify_user_by_id(meeting_id, "Falha ao gerar ata", "Não foi possível processar a gravação da reunião.")
  end

  private

  def notify_user(meeting, title, body)
    Notification.create!(
      user_id: meeting.creator_id,
      actor_id: meeting.creator_id,
      notifiable: meeting,
      kind: "meeting_minute",
      title: title,
      body: body,
      action_text: "Abrir ata",
      action_url: Rails.application.routes.url_helpers.action_plan_meeting_minute_path(
        meeting.action_plan_id, meeting.id
      )
    )
  rescue StandardError => e
    Rails.logger.error("Falha ao criar notificação da ata #{meeting.id}: #{e.class}: #{e.message}")
  end

  def notify_user_by_id(meeting_id, title, body)
    meeting = MeetingMinute.select(:id, :action_plan_id, :creator_id).find_by(id: meeting_id)
    notify_user(meeting, title, body) if meeting
  end
end
