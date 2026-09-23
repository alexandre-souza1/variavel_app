class AzHelperRemonteService
  PALETTE_RATE = BigDecimal("0.10")

  def initialize(start_date:, end_date:)
    @start_date, @end_date = start_date, end_date
  end

  def daily_values
    @daily_values ||= AzMapa.considerados_na_variavel.remonte
      .where(data: @start_date..@end_date, turno: [1], atingiu_meta: true)
      .order(:data).to_a
      .to_h { |map| [map.data, map.resultado.to_d * PALETTE_RATE] }
  end

  def total
    daily_values.values.sum(BigDecimal("0"))
  end
end
