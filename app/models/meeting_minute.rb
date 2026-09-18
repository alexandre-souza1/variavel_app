class MeetingMinute < ApplicationRecord
  belongs_to :action_plan
  belongs_to :creator, class_name: "User"
  belongs_to :collaborator, class_name: "User", optional: true
  has_one_attached :audio
  has_many :edits, class_name: "MeetingMinuteEdit", dependent: :destroy

  validates :title, :meeting_date, presence: true
  validates :audio, presence: true, on: :create
  validate :audio_size_limit, on: :create

  enum :status, {
    queued: "queued",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }

  def participants=(value)
    names = value.is_a?(String) ? value.split(/\r?\n/) : Array(value)
    super(names.map { |name| name.to_s.strip }.reject(&:blank?).uniq)
  end

  def original_decisions_for_display
    original_decisions.presence || first_edit_snapshot&.dig("before", "decisions") || []
  end

  def original_summary_for_display
    original_summary.presence || first_edit_snapshot&.dig("before", "summary") || ""
  end

  def original_pending_items_for_display
    original_pending_items.presence || first_edit_snapshot&.dig("before", "pending_items") || []
  end

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

  def first_edit_snapshot
    edits.order(:created_at).first&.changes_snapshot
  end
end
