class Download < ApplicationRecord
  CATEGORIES = ['PADRÃO', 'MATRIZ', 'LUP'].freeze
  FILE_TYPES = ['PDF', 'Excel', 'Word', 'PowerPoint'].freeze
  SECTOR = ['FROTA', 'ENTREGA', 'ARMAZEM', 'RH', 'FINANCEIRO', 'SEGURANÇA'].freeze

  validates :title, :category, :sector, :url, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp, message: "deve ser uma URL válida" }
end
