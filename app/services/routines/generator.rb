module Routines
  class Generator

    def self.call(...)
      new(...).call
    end

    def initialize(template:, period_start:, period_end:, created_by:)
      @template = template
      @period_start = period_start
      @period_end = period_end
      @created_by = created_by
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
                :created_by

    def create_routine
      Routine.create!(
        routine_template: template,
        created_by: created_by,
        title: default_title,
        period_start: period_start,
        period_end: period_end,
        status: :draft
      )
    end

    def create_values(routine)

      indicators = template
        .routine_categories
        .includes(:routine_indicators)
        .flat_map(&:routine_indicators)

      indicators.each do |indicator|

        (period_start..period_end).each do |date|

          RoutineValue.create!(

            routine: routine,

            routine_indicator: indicator,

            reference_date: date

          )

        end

      end

    end

    def default_title
      "#{template.name} - #{I18n.l(period_start, format: "%B/%Y")}"
    end

  end
end
