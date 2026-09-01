module Routines
  class IndicatorUpdater

    def self.call(...)
      new(...).call
    end

    def initialize(routine:, indicator_ids:)
      @routine = routine
      @indicator_ids = Array(indicator_ids).map(&:to_i)
    end

    def call
      ActiveRecord::Base.transaction do
        routine.update!(selected_indicator_ids: resolved_indicator_ids)
        remove_unselected_indicators
        add_missing_indicators
      end
    end

    private

    attr_reader :routine, :indicator_ids

    def resolved_indicator_ids
      return routine.default_selected_indicator_ids if indicator_ids.blank?

      selected_ids = Array(indicator_ids).map(&:to_i)
      locked_ids = locked_indicator_ids

      (selected_ids + locked_ids).uniq
    end

    def locked_indicator_ids
      routine.routine_values
        .where.not(value: [nil, ""])
        .distinct
        .pluck(:routine_indicator_id)
    end

    def remove_unselected_indicators
      selected_ids = routine.selected_indicator_ids
      return if selected_ids.blank?

      routine.routine_values
        .where.not(routine_indicator_id: selected_ids)
        .delete_all
    end

    def add_missing_indicators
      selected_ids = routine.selected_indicator_ids
      return if selected_ids.blank?

      selected_indicators = RoutineIndicator.where(id: selected_ids)
      routine.ensure_expected_values!(indicators: selected_indicators)
    end

  end
end
