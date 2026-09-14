class AiSetting < ApplicationRecord
  MODELS = {
    "Gemini 3.6 Flash" => "gemini-3.6-flash",
    "Gemini 3.1 Flash-Lite" => "gemini-3.1-flash-lite",
    "Gemini 3.5 Flash-Lite" => "gemini-3.5-flash-lite",
    "Gemini 2.5 Flash-Lite" => "gemini-2.5-flash-lite"
  }.freeze

  validates :primary_model, inclusion: { in: MODELS.values }
  validates :meeting_audio_max_minutes,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 180 }

  def self.current
    first_or_create!
  end

  def self.primary_model
    current.primary_model
  end
end
