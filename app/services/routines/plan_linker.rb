module Routines
  class PlanLinker
    def self.call(routine:, action_plan:, bucket_ids:)
      action_plan.with_lock do
        routine.lock!
        if routine.action_plan_id.present? && routine.action_plan_id != action_plan.id
          routine.errors.add(:action_plan, "já está vinculado a outro plano")
          raise ActiveRecord::RecordInvalid, routine
        end

        next routine if routine.action_plan_id == action_plan.id && routine.routine_template.action_plan_id == action_plan.id

        source = routine.routine_template
        source_categories = source.routine_categories.includes(routine_indicators: :routine_indicator_targets).to_a
        destinations = source_categories.to_h do |category|
          selected_id = bucket_ids[category.id.to_s]
          if selected_id.blank?
            routine.errors.add(:base, "Escolha um bucket para a categoria #{category.name}.")
            raise ActiveRecord::RecordInvalid, routine
          end
          bucket = if selected_id == "new"
            action_plan.buckets.find_by(name: category.name) || action_plan.buckets.create!(name: category.name, position: action_plan.buckets.count)
          else
            action_plan.buckets.find(selected_id)
          end
          [category.id, bucket]
        end
        template = PlanTemplateBuilder.call(action_plan: action_plan)
        PlanTemplateSynchronizer.call(action_plan: action_plan, template: template)
        selected_ids = routine.selected_indicator_ids
        adapted_ids = {}

        source_categories.each do |category|
          destination = template.routine_categories.find_by!(bucket: destinations.fetch(category.id))
          category.routine_indicators.each do |indicator|
            adapted = destination.routine_indicators.find_by(source_indicator_id: indicator.id)
            unless adapted
              attributes = indicator.attributes.slice("name", "description", "calculation_type", "value_type", "goal_direction", "response_frequency", "required", "active")
              adapted = destination.routine_indicators.create!(attributes.merge(source_indicator: indicator, position: destination.routine_indicators.count))
              indicator.routine_indicator_targets.each do |target|
                # Preserve persisted legacy goals, including formats accepted by older versions.
                copy = adapted.routine_indicator_targets.new(target.attributes.slice("goal", "starts_at", "ends_at"))
                copy.save!(validate: false)
              end
            end
            adapted_ids[indicator.id] = adapted.id
          end
        end

        routine.routine_values.find_each do |value|
          value.update_columns(routine_indicator_id: adapted_ids.fetch(value.routine_indicator_id))
        end
        routine.update!(action_plan: action_plan, routine_template: template,
          selected_indicator_ids: selected_ids.map { |id| adapted_ids.fetch(id) })
      end
      routine
    end
  end
end
