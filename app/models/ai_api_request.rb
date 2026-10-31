class AiApiRequest < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :collaborator, polymorphic: true, optional: true
  validates :collaborator_type, inclusion: { in: %w[Employee Driver Operator Ajudante AzAjudante] }, allow_nil: true
  FEATURES = { "assistant" => "Assistente pessoal", "daily_summary" => "Resumo do dia", "variable_chat" => "Chat de variável", "meeting" => "Atas de reunião", "checklist_tracking" => "Identificação de faltas de checklist", "theme_generation" => "Criação de temas" }.freeze

  scope :successful, -> { where(http_status: 200..299) }
  scope :rate_limited, -> { where(http_status: 429) }

  def self.current_credential_fingerprint
    fingerprint(ENV["GEMINI_API_KEY"].to_s)
  end

  def self.fingerprint(api_key)
    Digest::SHA256.hexdigest(api_key)
  end
end
