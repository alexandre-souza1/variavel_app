class AzHelperSuprimentoService
  DAILY_VALUE = BigDecimal("4.00")

  def initialize(start_date:, end_date:)
    @start_date, @end_date = start_date, end_date
  end

  def daily_values
    @daily_values ||= AzMapa.considerados_na_variavel.suprimento
      .where(data: @start_date..@end_date, turno: [0], atingiu_meta: true)
      .distinct.order(:data).pluck(:data).to_h { |date| [date, DAILY_VALUE] }
  end

  def total
    daily_values.values.sum(BigDecimal("0"))
  end
end
