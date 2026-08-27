require "test_helper"

class InvoiceGoalTest < ActiveSupport::TestCase
  test "normalizes month values to the first day of the month" do
    goal = InvoiceGoal.new(reference_month: "2026-08")

    assert_equal Date.new(2026, 8, 1), goal.reference_month
  end

  test "rejects categories from another sector" do
    goal = InvoiceGoal.new(name: "Custos de frota", sector: :frota, reference_month: "2026-08", target_amount: 1000)
    goal.budget_categories = [BudgetCategory.new(name: "Rota", sector: :rota)]

    goal.valid?

    assert_includes goal.errors[:budget_categories], "devem pertencer ao setor FROTA"
  end
end
