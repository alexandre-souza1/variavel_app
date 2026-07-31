require "test_helper"

class RoutineTest < ActiveSupport::TestCase
  test "ensure expected values creates missing weekly and monthly slots" do
    template = RoutineTemplate.create!(name: "Ensure expected values test")
    category = template.routine_categories.create!(
      name: "Main",
      position: 0
    )

    weekly_indicator = category.routine_indicators.create!(
      name: "Weekly",
      position: 0,
      response_frequency: :weekly
    )

    monthly_indicator = category.routine_indicators.create!(
      name: "Monthly",
      position: 1,
      response_frequency: :monthly
    )

    routine = template.routines.create!(
      created_by: users(:one),
      period_start: Date.new(2026, 7, 1),
      period_end: Date.new(2026, 7, 31),
      status: :open
    )

    routine.routine_values.create!(
      routine_indicator: weekly_indicator,
      reference_date: Date.new(2026, 7, 1)
    )

    assert_difference -> { routine.routine_values.count }, 5 do
      routine.ensure_expected_values!
    end

    assert routine.routine_values.exists?(
      routine_indicator: weekly_indicator,
      reference_date: Date.new(2026, 7, 6)
    )
    assert routine.routine_values.exists?(
      routine_indicator: monthly_indicator,
      reference_date: Date.new(2026, 7, 31)
    )
  end
end
