require "test_helper"

module Routines
  class IndicatorUpdaterTest < ActiveSupport::TestCase
    setup do
      @template = RoutineTemplate.create!(name: "Test template #{Time.current.to_i}")
      @category = @template.routine_categories.create!(name: "Main", position: 0)

      @daily_indicator = @category.routine_indicators.create!(
        name: "Daily",
        position: 0,
        response_frequency: :daily
      )

      @weekly_indicator = @category.routine_indicators.create!(
        name: "Weekly",
        position: 1,
        response_frequency: :weekly
      )

      @monthly_indicator = @category.routine_indicators.create!(
        name: "Monthly",
        position: 2,
        response_frequency: :monthly
      )

      @routine = Routine.create!(
        routine_template: @template,
        created_by: users(:one),
        title: "Test Routine",
        period_start: Date.new(2026, 7, 1),
        period_end: Date.new(2026, 7, 31),
        status: :open
      )

      @routine.ensure_expected_values!
    end

    test "removes values for unselected indicators" do
      assert_equal 36, @routine.routine_values.count

      Routines::IndicatorUpdater.call(
        routine: @routine,
        indicator_ids: [@daily_indicator.id, @weekly_indicator.id]
      )

      assert_equal 35, @routine.reload.routine_values.count
      assert_equal 0, @routine.routine_values.where(routine_indicator: @monthly_indicator).count
    end

    test "adds values for newly selected indicators" do
      routine = Routine.create!(
        routine_template: @template,
        created_by: users(:one),
        title: "Test Routine 2",
        period_start: Date.new(2026, 6, 1),
        period_end: Date.new(2026, 6, 30),
        status: :open
      )

      routine.ensure_expected_values!(indicators: [@daily_indicator])

      assert_equal 30, routine.routine_values.count

      Routines::IndicatorUpdater.call(
        routine: routine,
        indicator_ids: [@daily_indicator.id, @weekly_indicator.id]
      )

      assert_equal 35, routine.reload.routine_values.count
      assert_equal 30, routine.routine_values.where(routine_indicator: @daily_indicator).count
      assert_equal 5, routine.routine_values.where(routine_indicator: @weekly_indicator).count
    end

    test "keeps indicators with filled values selected" do
      @routine.routine_values.first.update!(value: "123")

      Routines::IndicatorUpdater.call(
        routine: @routine,
        indicator_ids: [@weekly_indicator.id, @monthly_indicator.id]
      )

      selected_ids = @routine.reload.selected_indicator_ids
      assert_includes selected_ids, @daily_indicator.id
      assert_includes selected_ids, @weekly_indicator.id
      assert_includes selected_ids, @monthly_indicator.id
    end

    test "handles empty indicator_ids" do
      Routines::IndicatorUpdater.call(
        routine: @routine,
        indicator_ids: nil
      )

      assert_equal 36, @routine.reload.routine_values.count
    end
  end
end



