require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "exposes the financial sector label" do
    assert_equal ["frota"], User.new(sector: :fleet).budget_sectors
    assert_equal ["rota", "as"], User.new(sector: :du).budget_sectors
    assert_equal "rota", User.new(sector: :du).budget_sector
    assert_equal "armazem", User.new(sector: :warehouse).budget_sector
    assert_equal "financeiro", User.new(sector: :finance).budget_sector
  end
end
