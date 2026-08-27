require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  test "rejects purchaser from a different sector" do
    invoice = Invoice.new(
      purchaser: User.new(sector: :finance),
      budget_category: BudgetCategory.new(name: "Manutenção", sector: :rota)
    )

    invoice.valid?

    assert_includes invoice.errors[:purchaser], "deve pertencer ao setor ROTA"
  end

  test "allows purchaser from the category sector" do
    invoice = Invoice.new(
      purchaser: User.new(sector: :finance),
      budget_category: BudgetCategory.new(name: "Serviços", sector: :financeiro)
    )

    invoice.valid?

    assert_not_includes invoice.errors[:purchaser], "deve pertencer ao setor FINANCEIRO"
  end
end
