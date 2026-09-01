require "test_helper"

module Routines
  class CalculationServiceTest < ActiveSupport::TestCase
    test "uses expected weekly slots for completion" do
      template = RoutineTemplate.create!(name: "Weekly calculation test")
      category = template.routine_categories.create!(
        name: "Main",
        position: 0
      )
      indicator = category.routine_indicators.create!(
        name: "Weekly indicator",
        position: 0,
        response_frequency: :weekly
      )
      routine = template.routines.create!(
        created_by: users(:one),
        period_start: Date.new(2026, 7, 1),
        period_end: Date.new(2026, 7, 31),
        status: :open
      )

      routine.routine_values.create!(
        routine_indicator: indicator,
        reference_date: Date.new(2026, 7, 6),
        value: 10
      )

      result = Routines::CalculationService.call(
        routine: routine,
        indicator: indicator
      )

      assert_equal 1, result[:filled_days]
      assert_equal 4, result[:total_days]
      assert_equal "semanas", result[:progress_label]
      assert_not result[:complete]
    end

    test "calculates duration average in minutes and seconds" do
      template = RoutineTemplate.create!(name: "Duration average test")
      category = template.routine_categories.create!(
        name: "Main",
        position: 0
      )
      indicator = category.routine_indicators.create!(
        name: "Duration indicator",
        position: 0,
        value_type: :duration,
        calculation_type: :ranged
      )
      routine = template.routines.create!(
        created_by: users(:one),
        period_start: Date.new(2026, 7, 1),
        period_end: Date.new(2026, 7, 2),
        status: :open
      )

      routine.routine_values.create!(
        routine_indicator: indicator,
        reference_date: Date.new(2026, 7, 1),
        value: "100:30"
      )
      routine.routine_values.create!(
        routine_indicator: indicator,
        reference_date: Date.new(2026, 7, 2),
        value: "101:30"
      )

      result = Routines::CalculationService.call(
        routine: routine,
        indicator: indicator
      )

      assert_equal "101:00", result[:value]
    end

    test "marks incomplete results as not achieved when routine is closed" do
      template = RoutineTemplate.create!(name: "Closed calculation test")
      category = template.routine_categories.create!(name: "Main", position: 0)
      indicator = category.routine_indicators.create!(
        name: "Daily indicator",
        position: 0,
        response_frequency: :daily,
        calculation_type: :ranged,
        value_type: :integer,
        goal_direction: :greater_or_equal
      )
      indicator.routine_indicator_targets.create!(
        starts_at: Date.new(2026, 7, 1),
        goal: "10"
      )
      routine = template.routines.create!(
        created_by: users(:one),
        period_start: Date.new(2026, 7, 1),
        period_end: Date.new(2026, 7, 2),
        status: :closed
      )
      routine.routine_values.create!(
        routine_indicator: indicator,
        reference_date: Date.new(2026, 7, 1),
        value: "10"
      )

      result = Routines::CalculationService.call(
        routine: routine,
        indicator: indicator
      )

      assert_equal :danger, result[:status]
      assert_not result[:complete]
    end
  end
end
