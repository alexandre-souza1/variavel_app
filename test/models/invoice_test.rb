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

  test "rejects an issue date after today" do
    invoice = Invoice.new(date_issued: Date.current + 1.day)

    invoice.valid?

    assert_includes invoice.errors[:date_issued], "não pode ser maior que a data atual"
  end

  test "allows today's issue date and a future due date" do
    invoice = Invoice.new(date_issued: Date.current, due_date: Date.current + 1.day)

    invoice.valid?

    assert_empty invoice.errors[:date_issued]
    assert_empty invoice.errors[:due_date]
  end
end
