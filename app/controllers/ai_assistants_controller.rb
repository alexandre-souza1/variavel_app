class AiAssistantsController < ApplicationController
  before_action :authenticate_user!
  before_action :private_response
  before_action :set_conversation

  def show
    @conversation.expire_request!
    render_conversation
  end

  def create
    question = params[:question].to_s.strip
    unless question.present? && question.length <= 2_000
      render json: { error: "Escreva uma pergunta com até 2.000 caracteres." }, status: :unprocessable_entity
      return
    end
    unless ENV["GEMINI_API_KEY"].present?
      render json: { error: "O assistente ainda não foi configurado. Solicite a configuração ao administrador." }, status: :service_unavailable
      return
    end

    @conversation.expire_request!
    reference = params[:page_context].is_a?(ActionController::Parameters) ? params[:page_context].permit(:type, :id).to_h : {}
    page = AiAssistant::PageContext.new(user: current_user, reference: reference)
    @conversation.ask!(question, page_context: page.reference)
    render_conversation(status: :accepted)
  rescue AiConversation::Busy
    render json: { error: "Aguarde a resposta da consulta em andamento." }, status: :conflict
  rescue AiConversation::RateLimited
    render json: { error: "Você atingiu 20 consultas nesta hora. Tente novamente mais tarde." }, status: :too_many_requests
  rescue AiAssistant::PageContext::Unavailable
    render json: { error: "A referência desta tela não está mais disponível. Remova o contexto ou abra o registro novamente." }, status: :unprocessable_entity
  rescue StandardError => error
    Rails.logger.error("Falha ao iniciar o assistente: #{error.class}")
    render json: { error: "Não foi possível iniciar a consulta. Tente novamente em instantes." }, status: :service_unavailable
  end

  def destroy
    @conversation.clear!
    render_conversation
  end

  private

  def private_response
    response.headers["Cache-Control"] = "no-store, private"
  end

  def set_conversation
    # A identidade vem exclusivamente da sessão autenticada.
    @conversation = AiConversation.create_or_find_by!(user: current_user)
  end

  def render_conversation(status: :ok)
    render json: AiAssistant::ConversationPayload.call(@conversation), status: status
  end
end
