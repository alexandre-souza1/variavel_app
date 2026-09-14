class PublicVariableChatController < ApplicationController
  before_action :load_identity, only: %i[index message logout]

  def index
    @history = Array(session.dig(:public_variable_chat, "history"))
  end

  def identify
    identity = PublicVariableIdentity.find(
      profile: params[:profile],
      registration: params[:registration],
      birth_date: params[:birth_date]
    )

    unless identity
      session[:public_variable_chat_open] = true if reopen_widget_after_return?
      redirect_to chat_return_path,
        alert: "Não encontramos esse cadastro. Confira o perfil, a matrícula e a data de nascimento."
      return
    end

    reset_chat_session(identity)
    session[:public_variable_chat_open] = true if reopen_widget_after_return?
    redirect_to chat_return_path, notice: "Olá, #{identity.name.split.first}! Como posso ajudar?"
  end

  def message
    unless @identity
      render_chat_error("Identifique-se para iniciar a consulta.", :unauthorized)
      return
    end

    question = params[:question].to_s.strip
    if question.blank?
      render_chat_error("Digite uma pergunta.", :unprocessable_entity)
      return
    end

    if message_count >= 20
      render_chat_error(
        "Você atingiu o limite de consultas desta sessão. Identifique-se novamente para continuar.",
        :too_many_requests
      )
      return
    end

    answer = PublicVariableChatService.new(
      identity: @identity,
      history: Array(session.dig(:public_variable_chat, "history")),
      question: question
    ).call

    add_message_to_history(question, answer)
    respond_to do |format|
      format.html { redirect_to public_variable_chat_path }
      format.json { render json: { answer: answer }, status: :ok }
    end
  rescue StandardError => e
    Rails.logger.error("Falha no chat público de variável: #{e.class}: #{e.message}")
    render_chat_error("Não foi possível responder agora. Tente novamente em instantes.", :service_unavailable)
  end

  def logout
    session.delete(:public_variable_chat)
    session[:public_variable_chat_open] = true if reopen_widget_after_return?
    redirect_to chat_return_path, notice: "Sessão encerrada."
  end

  private

  def load_identity
    data = session[:public_variable_chat]
    @identity = PublicVariableIdentity.from_session(data) if data.present?
  end

  def reset_chat_session(identity)
    session[:public_variable_chat] = {
      "profile" => identity.profile,
      "id" => identity.record.id,
      "history" => [],
      "message_count" => 0
    }
  end

  def chat_return_path
    candidate = params[:return_to].to_s
    return public_variable_chat_path unless candidate.start_with?("/") && !candidate.start_with?("//")

    candidate
  end

  def reopen_widget_after_return?
    candidate = params[:return_to].to_s
    return false if candidate.blank?

    candidate.split("?", 2).first != public_variable_chat_path
  end

  def add_message_to_history(question, answer)
    data = session[:public_variable_chat] || {}
    history = Array(data["history"])
    history << { "role" => "user", "content" => question.truncate(500) }
    history << { "role" => "assistant", "content" => answer.to_s.truncate(1500) }
    data["history"] = history.last(8)
    data["message_count"] = message_count + 1
    session[:public_variable_chat] = data
  end

  def message_count
    session.dig(:public_variable_chat, "message_count").to_i
  end

  def render_chat_error(message, status)
    respond_to do |format|
      format.html { redirect_to public_variable_chat_path, alert: message }
      format.json { render json: { error: message }, status: status }
    end
  end
end
