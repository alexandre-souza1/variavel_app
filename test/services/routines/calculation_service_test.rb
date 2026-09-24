require "test_helper"

module Routines
  class CalculationServiceTest < ActiveSupport::TestCase
    test "empty Sundays do not prevent daily completion in open or closed routines" do
      routine, indicator = sunday_calculation_setup
      add_calculation_value(routine, indicator, 4, "10")
      add_calculation_value(routine, indicator, 6, "10")
      add_calculation_value(routine, indicator, 5, nil)

      %i[open closed].each do |status|
        routine.update!(status: status)
        result = CalculationService.call(routine: routine, indicator: indicator)

        assert_equal :success, result[:status]
        assert result[:complete]
        assert_equal 2, result[:filled_days]
        assert_equal 2, result[:total_days]
        assert_equal 100.0, result[:completion]
      end
    end

    test "filled Sundays contribute to daily results with preloaded or queried values" do
      routine, indicator = sunday_calculation_setup
      add_calculation_value(routine, indicator, 4, "10")
      add_calculation_value(routine, indicator, 5, "4")
      add_calculation_value(routine, indicator, 6, "10")

      [nil, routine.routine_values.to_a].each do |values|
        result = CalculationService.call(
          routine: routine, indicator: indicator, values: values
        )

        assert_equal 8, result[:value]
        assert_equal :danger, result[:status]
        assert result[:complete]
        assert_equal 3, result[:filled_days]
        assert_equal 3, result[:total_days]
        assert_equal 100.0, result[:completion]
      end
    end

    test "filled Sundays do not replace missing required daily values" do
      routine, indicator = sunday_calculation_setup
      add_calculation_value(routine, indicator, 4, "10")
      add_calculation_value(routine, indicator, 5, "10")

      result = CalculationService.call(routine: routine, indicator: indicator)

      assert_equal :danger, result[:status]
      assert_not result[:complete]
      assert_equal 2, result[:filled_days]
      assert_equal 3, result[:total_days]
      assert_equal 66.7, result[:completion]
    end

    test "Sunday reference dates remain required for weekly and monthly indicators" do
      routine, indicator = sunday_calculation_setup
      routine.update!(
        period_end: Date.new(2026, 7, 31),
        weekly_reference_weekday: 0,
        monthly_reference_day: 5
      )

      { weekly: 4, monthly: 1 }.each do |frequency, total|
        indicator.update!(response_frequency: frequency)
        result = CalculationService.call(routine: routine, indicator: indicator)

        assert_equal total, result[:total_days]
        assert_not result[:complete]
      end
    end

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

    private

    def sunday_calculation_setup
      template = RoutineTemplate.create!(name: "Optional Sunday calculation")
      category = template.routine_categories.create!(name: "Main", position: 0)
      indicator = category.routine_indicators.create!(
        name: "Daily indicator", position: 0,
        response_frequency: :daily, calculation_type: :ranged,
        value_type: :integer, goal_direction: :greater_or_equal
      )
      indicator.routine_indicator_targets.create!(
        starts_at: Date.new(2026, 7, 1), goal: "10"
      )
      routine = template.routines.create!(
        created_by: users(:one),
        period_start: Date.new(2026, 7, 4),
        period_end: Date.new(2026, 7, 6), status: :closed
      )
      [routine, indicator]
    end

    def add_calculation_value(routine, indicator, day, value)
      routine.routine_values.create!(
        routine_indicator: indicator,
        reference_date: Date.new(2026, 7, day), value: value
      )
    end
  end
end
