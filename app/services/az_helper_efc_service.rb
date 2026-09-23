class AzHelperEfcService
  DAILY_VALUE = BigDecimal("5.00")

  def initialize(start_date:, end_date:)
    @start_date, @end_date = start_date, end_date
  end

  def daily_values
    # EFC is shared by helpers in A, B and C, including existing A/C maps.
    # Separate shift entries for the same day must not multiply the payment.
    @daily_values ||= AzMapa.considerados_na_variavel.eficiencia_carregamento
      .where(data: @start_date..@end_date, atingiu_meta: true)
      .distinct.order(:data).pluck(:data).to_h { |date| [date, DAILY_VALUE] }
  end

  def total
    daily_values.values.sum(BigDecimal("0"))
  end
end
