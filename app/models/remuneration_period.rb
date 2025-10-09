class RemunerationPeriod < ApplicationRecord
  has_many :vehicle_remunerations, dependent: :destroy
  accepts_nested_attributes_for :vehicle_remunerations, allow_destroy: true

  validates :label, :start_date, :end_date, presence: true
  validate :start_before_end

  def start_before_end
    if start_date && end_date && start_date > end_date
      errors.add(:start_date, "deve ser anterior à data final")
    end
  end

  # retorna array de hashes com :budget_category, :planned, :real, :diff
  def comparison_by_category
    planned = RemunerationCategoryValue
              .joins(:vehicle_remuneration)
              .where(vehicle_remunerations: { remuneration_period_id: id })
              .group(:budget_category_id)
              .sum(:value)

    real = Invoice
           .where(budget_category_id: BudgetCategory.pluck(:id), date: start_date..end_date)
           .group(:budget_category_id)
           .sum(:total)

    category_ids = (planned.keys + real.keys).uniq
    BudgetCategory.where(id: category_ids).map do |bc|
      p = planned[bc.id] || 0
      r = real[bc.id] || 0
      { budget_category: bc, planned: p.to_f, real: r.to_f, diff: (p.to_f - r.to_f) }
    end
  end
end
