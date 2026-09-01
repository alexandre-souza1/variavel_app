module Routines
  class Generator

    def self.call(...)
      new(...).call
    end

    def initialize(template:, period_start:, period_end:, created_by:, indicator_ids: nil)
      @template = template
      @period_start = period_start
      @period_end = period_end
      @created_by = created_by
      @indicator_ids = Array(indicator_ids).map(&:to_i)
    end

    def call
      ActiveRecord::Base.transaction do
        routine = create_routine

        create_values(routine)

        routine
      end
    end

    private

    attr_reader :template,
                :period_start,
                :period_end,
                :created_by,
                :indicator_ids

    def create_routine
      Routine.create!(
        routine_template: template,
        created_by: created_by,
        title: default_title,
        period_start: period_start,
        period_end: period_end,
        status: :open,
        selected_indicator_ids: resolved_indicator_ids
      )
    end

    def create_values(routine)
      routine.ensure_expected_values!(indicators: routine.selected_indicators)
    end

    def resolved_indicator_ids
      return template
        .routine_categories
        .includes(:routine_indicators)
        .flat_map { |category| category.routine_indicators.map(&:id) } if indicator_ids.blank?

      indicator_ids
    end

    def default_title
      "#{template.name} - #{I18n.l(period_start, format: "%B/%Y")}"
    end

  end
end
