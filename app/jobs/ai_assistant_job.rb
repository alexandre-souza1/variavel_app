class AiAssistantJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, token, message_id)
    conversation = AiConversation.find_by(id: conversation_id)
    return unless conversation&.request_token == token && conversation.user.active?

    message = conversation.ai_messages.find_by(id: message_id, role: "user")
    return unless message

    responder = AiAssistant::Responder.new(user: conversation.user, conversation: conversation, message: message)
    answer = responder.call
    conversation.finish!(token, answer: answer)
  rescue StandardError => error
    report = AiAssistant::ErrorReport.new(error, context: { job_id: job_id, conversation_id: conversation_id,
      message_id: message_id }.merge(responder.respond_to?(:diagnostics) ? responder.diagnostics : {}))
    report.log!
    conversation&.finish!(token, error: report.message)
  end
end
