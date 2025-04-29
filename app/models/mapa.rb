class Mapa < ApplicationRecord
  belongs_to :driver, foreign_key: :matric_motorista, primary_key: :promax, optional: true
  belongs_to :ajudante, foreign_key: :matric_ajudante, primary_key: :promax, optional: true

  def data_formatada
    return nil if data.blank?

    digitos = data.gsub(/\D/, '') # Remove não numéricos

    case digitos.length
    when 8
      dia = digitos[0..1]
      mes = digitos[2..3]
      ano = digitos[4..7]
    when 7
      dia = digitos[0]
      mes = digitos[1..2]
      ano = digitos[3..6]
    when 6
      dia = digitos[0]
      mes = digitos[1]
      ano = digitos[2..5]
    else
      return nil
    end

    Date.new(ano.to_i, mes.to_i, dia.to_i)
  rescue ArgumentError
    nil
  end
end
