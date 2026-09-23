class Mapa < ApplicationRecord
  CARGOS = EmployeeRole::CARGOS.values.freeze

  belongs_to :driver, foreign_key: :matric_motorista, primary_key: :promax, optional: true
  belongs_to :ajudante, foreign_key: :matric_ajudante, primary_key: :promax, optional: true
  belongs_to :cargo_override_user, class_name: 'User', optional: true
  has_many :mapa_cargo_overrides, dependent: :restrict_with_exception

  validate :ajudantes_diferentes
  validates :cargo_override, inclusion: { in: CARGOS }, allow_blank: true

  def employee_codes
    [matric_motorista, matric_ajudante, matric_ajudante_2].map(&:to_s).reject { |code| code.blank? || code == '0' }
  end

  def apply_cargo_override!(cargo:, reason:, user:)
    normalized_cargo = cargo.to_s.presence
    if normalized_cargo.present? && !CARGOS.include?(normalized_cargo)
      errors.add(:cargo_override, 'selecione um cargo válido')
      raise ActiveRecord::RecordInvalid, self
    end

    if normalized_cargo == cargo_override.to_s.presence
      return self if normalized_cargo.blank? || reason.to_s.strip.blank?
      return self
    end

    if reason.to_s.strip.blank?
      errors.add(:cargo_override_reason, 'informe o motivo da alteração do cargo do mapa')
      raise ActiveRecord::RecordInvalid, self
    end

    self.class.transaction do
      lock!
      previous_cargo = cargo_override
      update!(cargo_override: normalized_cargo, cargo_override_reason: normalized_cargo ? reason.to_s.strip : nil,
        cargo_override_user: user, cargo_override_at: Time.current)
      mapa_cargo_overrides.create!(user: user, previous_cargo: previous_cargo, cargo: normalized_cargo,
        reason: reason.to_s.strip)
    end
    self
  end

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
