class Mapa < ApplicationRecord
  belongs_to :driver, foreign_key: :matric_motorista, primary_key: :promax, optional: true
  belongs_to :ajudante, foreign_key: :matric_ajudante, primary_key: :promax, optional: true

  validate :ajudantes_diferentes

  def ajudantes_diferentes
    # ✔️ Permitir que ambos sejam "0" (Nenhum), então só faz a validação se forem diferentes de "0"

    # Se ajudante 2 está preenchido (diferente de "0" ou vazio), mas ajudante 1 é vazio ou "0"
    if (matric_ajudante.blank? || matric_ajudante == "0") && matric_ajudante_2.present? && matric_ajudante_2 != "0"
      errors.add(:matric_ajudante_2, "não pode ser preenchido sem o Ajudante 1")
    end

    # Se ambos estão preenchidos (e não são "0") e são iguais
    if matric_ajudante.present? && matric_ajudante_2.present? &&
      matric_ajudante != "0" && matric_ajudante_2 != "0" &&
      matric_ajudante == matric_ajudante_2
      errors.add(:matric_ajudante_2, "não pode ser igual ao Ajudante 1")
    end
  end


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
