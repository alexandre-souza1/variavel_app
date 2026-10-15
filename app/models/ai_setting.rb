class AiSetting < ApplicationRecord
  MODELS = {
    "Gemini 3.6 Flash" => "gemini-3.6-flash",
    "Gemini 3.1 Flash-Lite" => "gemini-3.1-flash-lite",
    "Gemini 3.5 Flash-Lite" => "gemini-3.5-flash-lite",
    "Gemini 2.5 Flash-Lite" => "gemini-2.5-flash-lite"
  }.freeze

  QUOTA_DIMENSIONS = { "rpm" => "Requisições/minuto", "tpm" => "Tokens de entrada/minuto", "rpd" => "Requisições/dia" }.freeze

  before_validation :normalize_model_limits
  validate :valid_model_limits

  validates :primary_model, inclusion: { in: MODELS.values }
  validates :meeting_audio_max_minutes,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 180 }

  def self.current
    first_or_create!
  end

  def self.primary_model
    current.primary_model
  end

  private

  def normalize_model_limits
    return unless model_limits.is_a?(Hash)

    self.model_limits = model_limits.transform_values do |limits|
      next limits unless limits.is_a?(Hash)

      limits.transform_values do |value|
        if value.is_a?(String) && value.strip.match?(/\A\d+\z/)
          value.to_i
        else
          value.presence
        end
      end
    end
  end

  def valid_model_limits
    unless model_limits.is_a?(Hash)
      errors.add(:base, "Informe limites válidos para os modelos.")
      return
    end

    model_limits.each do |model, limits|
      unless MODELS.value?(model) && limits.is_a?(Hash)
        errors.add(:base, "Modelo de IA inválido nos limites.")
        next
      end
      limits.each do |dimension, value|
        next if QUOTA_DIMENSIONS.key?(dimension) && (value.nil? || (value.is_a?(Integer) && value.between?(0, 1_000_000_000_000)))

        errors.add(:base, "#{MODELS.key(model)}: os limites devem ser números inteiros de 0 a 1.000.000.000.000, ou ficar em branco.")
      end
    end
  end
end
