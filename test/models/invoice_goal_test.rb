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

  test "an open validity repeats monthly including across years but never before its start" do
    goal = create_goal("2026-08")

    assert_empty InvoiceGoal.effective_on(Date.new(2026, 7, 31))
    assert_equal [goal], InvoiceGoal.effective_on(Date.new(2026, 8, 31)).to_a
    assert_equal [goal], InvoiceGoal.effective_on(Date.new(2027, 1, 1)).to_a
  end

  test "the latest applicable validity replaces the target without changing history" do
    original = create_goal("2026-08")
    revised = create_goal("2026-10", target_amount: 2000)

    assert_equal [original], InvoiceGoal.effective_on(Date.new(2026, 9, 1)).to_a
    assert_equal [revised], InvoiceGoal.effective_on(Date.new(2026, 10, 1)).to_a
    assert_equal [revised], InvoiceGoal.effective_on(Date.new(2027, 1, 1)).to_a
    assert_equal 1000, original.reload.target_amount
  end

  test "end month is inclusive and a temporary validity falls back like GEROT" do
    original = create_goal("2026-08", ends_at: "2026-12")
    temporary = create_goal("2026-10", ends_at: "2026-11", target_amount: 2000)

    assert_equal Date.new(2026, 11, 30), temporary.ends_at
    assert_equal [temporary], InvoiceGoal.effective_on(Date.new(2026, 11, 30)).to_a
    assert_equal [original], InvoiceGoal.effective_on(Date.new(2026, 12, 31)).to_a
    assert_empty InvoiceGoal.effective_on(Date.new(2027, 1, 1))
  end

  test "validities do not replace different indicators or sectors and retain filters" do
    original = create_goal("2026-08")
    other_indicator = create_goal("2026-09", name: "Combustível")
    other_sector = create_goal("2026-10", sector: :rota,
      budget_categories: [BudgetCategory.create!(name: "Rota vigente", sector: :rota)])
    date = Date.new(2026, 10, 1)

    assert_equal [original.id, other_indicator.id].sort, InvoiceGoal.effective_on(date).where(sector: :frota).ids.sort
    assert_equal [other_sector], InvoiceGoal.where(sector: :rota).effective_on(date).to_a
  end

  test "rejects an end before the start and duplicate starts for the same indicator" do
    create_goal("2026-08")
    duplicate = InvoiceGoal.new(name: "Custos de frota", sector: :frota, reference_month: "2026-08")
    duplicate.valid?
    assert duplicate.errors[:name].any?

    invalid = create_goal("2026-09")
    invalid.ends_at = "2026-08"
    assert_not invalid.valid?
    assert_includes invalid.errors[:ends_at], "não pode ser anterior ao mês inicial"
  end

  test "changing a target creates a recurring entry and preserves past amounts and categories" do
    original = create_goal("2026-08", ends_at: "2026-08")
    revised_category = BudgetCategory.create!(name: "Categoria revisada", sector: :frota)

    revised = original.change_from(reference_month: "2026-10", target_amount: 2000,
      budget_category_ids: [revised_category.id])

    assert revised.persisted?
    assert_nil revised.ends_at
    assert_equal original.name, revised.name
    assert_equal 1000, original.reload.target_amount
    assert_equal [revised_category], revised.budget_categories
    refute_includes original.budget_categories, revised_category
    assert_equal [revised], InvoiceGoal.effective_on(Date.new(2027, 1, 1)).to_a
    assert_empty InvoiceGoal.effective_on(Date.new(2026, 9, 1))
  end

  test "changing an existing start month corrects that entry and preserves scheduled changes" do
    original = create_goal("2026-08", ends_at: "2026-08")
    scheduled = create_goal("2026-12", target_amount: 3000)
    assert_no_difference "InvoiceGoal.count" do
      revised = original.change_from(reference_month: "2026-08", target_amount: 2000)
      assert_equal original.id, revised.id
      assert_empty revised.errors
    end
    assert_nil original.reload.ends_at
    assert_equal 2000, original.target_amount
    assert_equal [scheduled], InvoiceGoal.effective_on(Date.new(2026, 12, 1)).to_a
  end

  test "invalid changes roll back category assignments as well as the target" do
    original = create_goal("2026-08")
    original_categories = original.budget_category_ids
    category = BudgetCategory.create!(name: "Outra categoria", sector: :frota)
    revised = original.change_from(reference_month: "2026-08", target_amount: -1, budget_category_ids: [category.id])
    assert revised.errors[:target_amount].any?
    assert_equal 1000, original.reload.target_amount
    assert_equal original_categories, original.budget_category_ids

    assert_no_difference "InvoiceGoal.count" do
      revised = original.change_from(reference_month: "2026-10", target_amount: 2000, budget_category_ids: [])
      assert revised.errors[:budget_categories].any?
    end
  end

  private

  def create_goal(month, **attributes)
    InvoiceGoal.create!({ name: "Custos de frota", sector: :frota,
      reference_month: month, target_amount: 1000,
      budget_categories: [BudgetCategory.create!(name: "Categoria #{month}", sector: :frota)] }.merge(attributes))
  end
end
