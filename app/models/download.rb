class Download < ApplicationRecord
  has_one_attached :file

  CATEGORIES = ['PADRÃO', 'MATRIZ', 'LUP'].freeze

  FILE_TYPES = ['PDF', 'Excel', 'Word', 'PowerPoint'].freeze

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

end
