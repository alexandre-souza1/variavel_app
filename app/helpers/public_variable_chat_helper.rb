module PublicVariableChatHelper
  def public_variable_chat_widget
    render "public_variable_chat/widget",
      identity: PublicVariableIdentity.from_session(session[:public_variable_chat]),
      history: Array(session.dig(:public_variable_chat, "history")),
      open: session.delete(:public_variable_chat_open)
  end

  def clean_public_variable_chat_text(text)
    text.to_s
      .gsub(/\\n/, "\n")
      .gsub(/\\(?:\r?\n|$)/, "\n")
      .gsub(/\\([*_~-])/, '\\1')
      .gsub(/\*\*(.*?)\*\*/, '\\1')
      .gsub(/^\s*\*\s+/, "• ")
      .strip
  end
end
