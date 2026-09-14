class MeetingMinute < ApplicationRecord
  belongs_to :action_plan
  belongs_to :creator, class_name: "User"
  has_one_attached :audio

  validates :title, :meeting_date, presence: true
  validates :audio, presence: true, on: :create
  validate :audio_size_limit, on: :create

  enum :status, {
    queued: "queued",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }

  def self.max_audio_size_mb
    ENV.fetch("MEETING_AUDIO_MAX_MB", "100").to_i
  end

  private

  def audio_size_limit
    return unless audio.attached? && audio.byte_size > max_audio_size

    errors.add(:audio, "deve ter no máximo #{max_audio_size / 1.megabyte} MB para processamento")
  end

  def max_audio_size
    self.class.max_audio_size_mb.megabytes
  end
end
