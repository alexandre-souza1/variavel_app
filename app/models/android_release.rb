require "digest"
require "zip"

class AndroidRelease < ApplicationRecord
  APPLICATION_ID = "br.com.log20.variavel".freeze
  MAX_APK_SIZE = 150.megabytes
  CHANNELS = %w[release debug].freeze

  has_one_attached :apk
  attr_accessor :apk_upload

  before_validation :prepare_apk, on: :create
  validates :channel, inclusion: { in: CHANNELS }
  validates :version_name, presence: true, length: { maximum: 50 }
  validates :version_code, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 2_100_000_000 },
                           uniqueness: { scope: :channel }
  validates :notes, length: { maximum: 4000 }
  validates :sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :byte_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_APK_SIZE }
  validate { errors.add(:apk, "é obrigatório") unless apk.attached? }

  scope :available, -> { where(published: true).with_attached_apk }

  def self.latest(channel)
    available.where(channel: channel).order(version_code: :desc).first
  end

  private

  def prepare_apk
    return unless apk_upload
    upload = apk_upload
    self.apk_upload = nil
    unless upload.respond_to?(:tempfile) && upload.original_filename.to_s.downcase.end_with?(".apk") &&
           upload.size.between?(1, MAX_APK_SIZE)
      errors.add(:apk, "deve ser um arquivo .apk de até 150 MB")
      return
    end

    Zip::File.open(upload.tempfile.path) do |archive|
      unless archive.find_entry("AndroidManifest.xml")
        errors.add(:apk, "não contém um aplicativo Android")
        return
      end
    end
    self.sha256 = Digest::SHA256.file(upload.tempfile.path).hexdigest
    self.byte_size = upload.size
    apk.attach(io: upload.tempfile, filename: "logia-#{channel}-#{version_code}.apk",
               content_type: "application/vnd.android.package-archive", identify: false)
  rescue Zip::Error, IOError, Errno::ENOENT
    errors.add(:apk, "não é um APK válido")
  end
end
