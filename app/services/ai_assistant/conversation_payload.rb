module AiAssistant
  class ConversationPayload
    def self.call(conversation)
      messages = conversation.ai_messages.includes(:ai_action_requests).order(id: :desc).limit(60).to_a.reverse
      {
        messages: messages.map do |message|
          message.as_json(only: %i[id role content sources]).merge(
            "actions" => message.ai_action_requests.sort_by(&:id).map(&:client_json)
          )
        end,
        processing: conversation.processing?, error: conversation.error_message
      }
    end
  end
end
