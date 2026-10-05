require "test_helper"

module Routines
  class GoalEvaluationTest < ActiveSupport::TestCase
    test "compares numbers using the goal direction and accepts zero and decimal commas" do
      indicator = RoutineIndicator.new(value_type: :decimal, calculation_type: :ranged, goal_direction: :less_or_equal)
      assert_equal :success, GoalEvaluation.call(indicator: indicator, value: "0", goal: "5")
      assert_equal :success, GoalEvaluation.call(indicator: indicator, value: "4,5", goal: "5")
      assert_equal :danger, GoalEvaluation.call(indicator: indicator, value: "6", goal: "5")
      indicator.goal_direction = :greater_or_equal
      assert_equal :danger, GoalEvaluation.call(indicator: indicator, value: "4", goal: "5")
      assert_equal :success, GoalEvaluation.call(indicator: indicator, value: "5", goal: "5")
    end

    test "compares boolean date time and duration indicators" do
      {
        boolean: ["false", "true"],
        date: ["2026-01-01", "2026-01-02"],
        time: ["09:30", "10:00"],
        duration: ["3:59", "4:00"]
      }.each do |type, (value, goal)|
        indicator = RoutineIndicator.new(value_type: type, calculation_type: :last_value, goal_direction: :greater_or_equal)
        assert_equal :danger, GoalEvaluation.call(indicator: indicator, value: value, goal: goal), type
        indicator.goal_direction = :less_or_equal
        assert_equal :success, GoalEvaluation.call(indicator: indicator, value: value, goal: goal), type
      end
    end

    test "missing goals missing values manual indicators and malformed comparisons have no status" do
      indicator = RoutineIndicator.new(value_type: :decimal, calculation_type: :ranged)
      assert_nil GoalEvaluation.call(indicator: indicator, value: "", goal: "5")
      assert_nil GoalEvaluation.call(indicator: indicator, value: "2", goal: nil)
      assert_nil GoalEvaluation.call(indicator: indicator, value: "oops", goal: "5")
      indicator.calculation_type = :manual_calculation
      assert_nil GoalEvaluation.call(indicator: indicator, value: "9", goal: "5")
      indicator.assign_attributes(calculation_type: :last_value, value_type: :time)
      assert_nil GoalEvaluation.call(indicator: indicator, value: "25:00", goal: "10:00")
    end
  end
end
