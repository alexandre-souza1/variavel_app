require "csv"
class Plate < ApplicationRecord
  validates :placa, presence: true, uniqueness: true
  has_many :checklists

  # Se quiser validar opções específicas
  SETORES = %w[ARMAZEM ROTA]
  TIPOS = ['Empilhadeira', 'Paleteira', 'Máquina de Limpeza', 'Caminhão', 'Van']
  PERFIS = ['GLP', 'Sem Balança', 'VUC', 'TOCO', 'TRUCK', 'BITRUCK', 'VAN', nil]

  validates :setor, inclusion: { in: SETORES }
  validates :tipo, inclusion: { in: TIPOS }
  validates :perfil, inclusion: { in: PERFIS }, allow_nil: true

  def self.import(file)
    csv_text = file.read.force_encoding("ISO-8859-1").encode("UTF-8")

    CSV.parse(csv_text, headers: true, col_sep: ';') do |row|
      cleaned_row = row.to_hash.transform_keys { |key| key.strip.downcase } # <- Limpa os headers
      plate_data = cleaned_row.symbolize_keys

      Plate.find_or_create_by(placa: plate_data[:placa]) do |plate|
        plate.setor  = plate_data[:setor]
        plate.perfil = plate_data[:perfil]
        plate.tipo   = plate_data[:tipo]
      end
    end
  end
end
