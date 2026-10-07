class AzOperatorOnDemandService
  RATE = AzRvOnDemandActivity::RV_RATES.fetch(:ondemand_operacional)

  attr_reader :activities

  def initialize(employee_name: nil, person: nil, start_date:, end_date:)
    scope = person ? AzRvOnDemandActivity.for_person(person) : AzRvOnDemandActivity.for_employee(employee_name)
    @activities = scope.between(start_date, end_date)
      .order(:created_at_source).select { |activity| activity.rv_category == :ondemand_operacional }
  end

  def quantity
    activities.sum(BigDecimal("0"), &:rv_quantity)
  end

  def total
    quantity * RATE
  end

  def daily
    activities.group_by { |activity| activity.created_at_source.to_date }.map do |date, records|
      quantity = records.sum(BigDecimal("0"), &:rv_quantity)
      { date: date, quantity: quantity, value: quantity * RATE }
    end
  end
end
