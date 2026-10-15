class AiAssistantJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, token, message_id)
    conversation = AiConversation.find_by(id: conversation_id)
    return unless conversation&.request_token == token && conversation.user.active?

    message = conversation.ai_messages.find_by(id: message_id, role: "user")
    return unless message

    answer = AiAssistant::Responder.new(user: conversation.user, conversation: conversation, message: message).call
    conversation.finish!(token, answer: answer)
  rescue StandardError => error
    Rails.logger.error("Falha no assistente de IA: #{error.class}")
    conversation&.finish!(token, error: "Não foi possível responder agora. Tente novamente em instantes.")
  end
end
