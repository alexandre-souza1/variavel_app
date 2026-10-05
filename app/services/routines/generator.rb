module Routines
  class Generator

    def self.call(...)
      new(...).call
    end

    def initialize(template:, period_start:, period_end:, created_by:, indicator_ids: nil, action_plan: nil, bucket_ids: {}, task_generation_mode: :commented_deviation)
      @template = template
      @period_start = period_start
      @period_end = period_end
      @created_by = created_by
      @indicator_ids = Array(indicator_ids).map(&:to_i)
      @action_plan = action_plan
      @bucket_ids = bucket_ids
      @task_generation_mode = task_generation_mode
    end

    def call
      ActiveRecord::Base.transaction do
        routine = create_routine

        create_values(routine)

        if @action_plan
          CategoryBucketMapper.call(
            action_plan: @action_plan,
            categories: routine.selected_indicators.map(&:routine_category).uniq,
            bucket_ids: @bucket_ids
          )
        end

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
        action_plan: @action_plan,
        created_by: created_by,
        title: default_title,
        period_start: period_start,
        period_end: period_end,
        status: :open,
        task_generation_mode: @task_generation_mode,
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

      selected_ids = template.routine_categories.joins(:routine_indicators)
        .where(routine_indicators: { id: indicator_ids })
        .pluck("routine_indicators.id")
      raise ArgumentError, "Selecione indicadores deste modelo de GEROT." unless selected_ids.sort == indicator_ids.uniq.sort

      selected_ids
    end

    def default_title
      "#{template.name} - #{I18n.l(period_start, format: "%B/%Y")}"
    end

  end
end
