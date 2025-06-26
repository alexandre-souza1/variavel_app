class AzMapa < ApplicationRecord
  enum tipo: {
    tempo_atendimento: 0,
    eficiencia_carregamento: 1,
    eficiencia_descarga: 2
  }

  # Constante para mapear os turnos
  TURNOS = {
    0 => "A",
    1 => "B",
    2 => "C"
  }.freeze

  validates :data, :tipo, :resultado, presence: true
  validates :turno, presence: true

  # Validação de unicidade personalizada para evitar registros duplicados
  validate :unicidade_por_dia_e_turnos

  # Helper para exibir os turnos como letras
  def turnos_em_texto
    turno.map { |t| TURNOS[t] }.join(", ")
  end

  private

  def unicidade_por_dia_e_turnos
    return if turno.blank?

    turno.each do |t|
      if AzMapa.where(data: data, tipo: tipo).where("turno @> ARRAY[?]::integer[]", t).exists?
        errors.add(:turno, "com tipo #{tipo} já foi lançado para esse dia e turno #{TURNOS[t]}")
      end
    end
  end
end
