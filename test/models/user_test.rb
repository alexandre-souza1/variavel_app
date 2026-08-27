require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "exposes the financial sector label" do
    assert_equal ["FROTA"], User.new(sector: :fleet).budget_sectors
    assert_equal ["ROTA", "AS"], User.new(sector: :du).budget_sectors
    assert_equal "ROTA", User.new(sector: :du).budget_sector
    assert_equal "ARMAZEM", User.new(sector: :warehouse).budget_sector
    assert_equal "FINANCEIRO", User.new(sector: :finance).budget_sector
  end
end
