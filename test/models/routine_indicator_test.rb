require "test_helper"

class RoutineIndicatorTest < ActiveSupport::TestCase
  test "daily reference dates include every date in the period" do
    indicator = routine_indicators(:one)
    indicator.response_frequency = :daily

    assert_equal [
      Date.new(2026, 7, 1),
      Date.new(2026, 7, 2),
      Date.new(2026, 7, 3)
    ], indicator.reference_dates_between(
      Date.new(2026, 7, 1),
      Date.new(2026, 7, 3)
    )
  end

  test "weekly reference dates use mondays in the period" do
    indicator = routine_indicators(:one)
    indicator.response_frequency = :weekly

    assert_equal [
      Date.new(2026, 7, 6),
      Date.new(2026, 7, 13),
      Date.new(2026, 7, 20),
      Date.new(2026, 7, 27)
    ], indicator.reference_dates_between(
      Date.new(2026, 7, 1),
      Date.new(2026, 7, 31)
    )
  end

  test "monthly reference dates use one slot per month" do
    indicator = routine_indicators(:one)
    indicator.response_frequency = :monthly

    assert_equal [
      Date.new(2026, 7, 31)
    ], indicator.reference_dates_between(
      Date.new(2026, 7, 1),
      Date.new(2026, 7, 31)
    )
  end

  test "monthly reference dates use month ends across many months" do
    indicator = routine_indicators(:one)
    indicator.response_frequency = :monthly

    assert_equal [
      Date.new(2026, 7, 31),
      Date.new(2026, 8, 31),
      Date.new(2026, 9, 30)
    ], indicator.reference_dates_between(
      Date.new(2026, 7, 1),
      Date.new(2026, 9, 30)
    )
  end
end
