require "test_helper"

module Routines
  class GeneratorTest < ActiveSupport::TestCase
    test "creates one value per expected indicator reference date" do
      template = RoutineTemplate.create!(name: "Routine frequency test")
      category = template.routine_categories.create!(
        name: "Main",
        position: 0
      )

      category.routine_indicators.create!(
        name: "Daily",
        position: 0,
        response_frequency: :daily
      )

      category.routine_indicators.create!(
        name: "Weekly",
        position: 1,
        response_frequency: :weekly
      )

      category.routine_indicators.create!(
        name: "Monthly",
        position: 2,
        response_frequency: :monthly
      )

      routine = Routines::Generator.call(
        template: template,
        period_start: Date.new(2026, 7, 1),
        period_end: Date.new(2026, 7, 31),
        created_by: users(:one)
      )

      assert_equal 36, routine.routine_values.count
      assert_equal 31, values_count_for(routine, "Daily")
      assert_equal 4, values_count_for(routine, "Weekly")
      assert_equal 1, values_count_for(routine, "Monthly")
    end

    private

    def values_count_for(routine, indicator_name)
      indicator = RoutineIndicator.find_by!(name: indicator_name)

      routine
        .routine_values
        .where(routine_indicator: indicator)
        .count
    end
  end
end
