class AzRvPoint < ApplicationRecord
  belongs_to :az_rv_import

  scope :between, ->(start_date, end_date) { where(reference_date: start_date..end_date) }

  POINT_RATE = BigDecimal("0.00141")

  def montagem_value
    # O relatório de pontos já traz o valor oficial calculado. Quando ele não
    # estiver preenchido, aplica-se a taxa fixa de R$ 0,00141 por ponto.
    return reported_value.to_d if reported_value.to_d.positive?

    total_points.to_d * POINT_RATE
  end
end
