class Download < ApplicationRecord
  has_one_attached :file

  CATEGORIES = ['PADRÃO', 'MATRIZ', 'LUP'].freeze

  FILE_TYPES = ['PDF', 'Excel', 'Word', 'PowerPoint'].freeze

  ALLOWED_URL_HOSTS = %w[
    drive.google.com
    docs.google.com
    onedrive.live.com
  ].freeze

  SECTOR = [
    'FROTA',
    'ENTREGA',
    'ARMAZEM',
    'RH',
    'FINANCEIRO',
    'SEGURANÇA'
  ].freeze

  validates :title, :category, :sector, presence: true

  validates :category, inclusion: { in: CATEGORIES }

  validates :url,
            format: {
              with: URI::DEFAULT_PARSER.make_regexp,
              message: "deve ser uma URL válida"
            },
            allow_blank: true

  validate :file_or_url_present

  validate :only_one_source

  validate :allowed_shared_url_host, if: :url_present?

  def safe_url?
    return false if url.blank?

    uri = URI.parse(url)
    return false unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    host = uri.host.to_s.downcase
    return false if host.empty?

    ALLOWED_URL_HOSTS.include?(host) || host.end_with?('.sharepoint.com')
  rescue URI::InvalidURIError
    false
  end

  private

  def file_or_url_present
    return if file.attached? || url.present?

    errors.add(:base, "Informe uma URL ou envie um arquivo")
  end

  def only_one_source
    if file.attached? && url.present?
      errors.add(:base, "Escolha apenas uma origem para o documento")
    elsif !file.attached? && url.blank?
      errors.add(:base, "Informe uma URL ou envie um arquivo")
    end
  end

  def url_present?
    url.present?
  end

  def allowed_shared_url_host
    return if safe_url?

    errors.add(:url, "deve ser um link compartilhado do Google Drive ou Microsoft OneDrive")
  end
end
