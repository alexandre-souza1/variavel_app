module Routines
  class PlanTemplateSynchronizer
    def self.call(action_plan:, template: nil)
      template ||= RoutineTemplate.find_by(action_plan_id: action_plan.id)
      return unless template

      action_plan.with_lock do
        action_plan.buckets.reorder(:position, :id).each do |bucket|
          category = template.routine_categories.find_or_initialize_by(bucket: bucket)
          if category.new_record?
            category.save!
          elsif category.name != bucket.name || category.position != bucket.position
            category.update_columns(name: bucket.name, position: bucket.position, updated_at: Time.current)
          end
          mapping = action_plan.routine_category_buckets.find_or_initialize_by(routine_category: category)
          mapping.update!(bucket: bucket) if mapping.new_record? || mapping.bucket_id != bucket.id
        end
      end
      template
    end
  end
end
