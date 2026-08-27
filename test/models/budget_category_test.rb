require "test_helper"

class BudgetCategoryTest < ActiveSupport::TestCase
  test "maps financial sectors to user sectors" do
    assert_equal :fleet, BudgetCategory.new(sector: :frota).user_sector
    assert_equal :du, BudgetCategory.new(sector: :rota).user_sector
    assert_equal :du, BudgetCategory.new(sector: :as).user_sector
    assert_equal :warehouse, BudgetCategory.new(sector: :armazem).user_sector
    assert_equal :finance, BudgetCategory.new(sector: :financeiro).user_sector
  end
end
