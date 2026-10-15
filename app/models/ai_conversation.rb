class AiConversation < ApplicationRecord
  class Busy < StandardError; end
  class RateLimited < StandardError; end

  belongs_to :user
  has_many :ai_messages, dependent: :delete_all

  def processing?
    request_token.present?
  end

  def expire_request!
    with_lock do
      if processing? && (requested_at.nil? || requested_at < 5.minutes.ago)
        update!(request_token: nil, error_message: "A consulta demorou demais. Envie sua pergunta novamente.")
      end
    end
  end

  def ask!(question)
    token = nil
    message = nil
    with_lock do
      raise Busy if processing?
      if usage_window_at.nil? || usage_window_at < 1.hour.ago
        self.usage_window_at = Time.current
        self.usage_count = 0
      end
      raise RateLimited if usage_count >= 20

      message = ai_messages.create!(role: "user", content: question)
      token = SecureRandom.uuid
      update!(request_token: token, requested_at: Time.current, error_message: nil, usage_count: usage_count + 1)
    end
    # Enfileira após o commit para o worker enxergar a mensagem e o token.
    begin
      job = AiAssistantJob.perform_later(id, token, message.id)
      raise ActiveJob::EnqueueError, "Assistente não enfileirado" unless job
    rescue StandardError
      finish!(token, error: "Não foi possível iniciar a consulta. Tente novamente em instantes.")
      raise
    end
  end

  def clear!
    with_lock do
      ai_messages.delete_all
      update!(request_token: nil, requested_at: nil, error_message: nil)
    end
  end

  def finish!(token, answer: nil, error: nil)
    with_lock do
      return unless request_token == token

      ai_messages.create!(role: "assistant", content: answer.fetch(:content), sources: answer.fetch(:sources)) if answer
      update!(request_token: nil, error_message: error)
    end
  end
end
