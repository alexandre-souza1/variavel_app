module PublicVariableChatHelper
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
