class AiAssistantActionsController < ApplicationController
  before_action :authenticate_user!
  before_action :private_response

  def confirm
    action = current_user.ai_action_requests.find(params[:id])
    action.confirm!(params[:confirmation_token])
    render json: AiAssistant::ConversationPayload.call(action.ai_conversation.reload)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Ação não encontrada ou sem acesso." }, status: :not_found
  rescue AiAssistant::ActionDraft::Forbidden => error
    render json: { error: error.message }, status: :forbidden
  rescue AiAssistant::ActionDraft::Stale => error
    render json: { error: error.message }, status: :conflict
  rescue AiActionRequest::ConfirmationRequired, AiAssistant::ActionDraft::Invalid => error
    render json: { error: error.message }, status: :unprocessable_entity
  rescue AiActionRequest::Conflict => error
    render json: { error: error.message }, status: :conflict
  rescue ActiveRecord::RecordInvalid
    render json: { error: "Não foi possível salvar os registros. Confira os dados e solicite uma nova proposta." }, status: :unprocessable_entity
  end

  def cancel
    action = current_user.ai_action_requests.find(params[:id])
    action.cancel!
    render json: AiAssistant::ConversationPayload.call(action.ai_conversation.reload)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Ação não encontrada ou sem acesso." }, status: :not_found
  rescue AiActionRequest::Conflict => error
    render json: { error: error.message }, status: :conflict
  end

  private

  def private_response
    response.headers["Cache-Control"] = "no-store, private"
  end
end
