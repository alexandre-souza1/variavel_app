module Routines
  class CategoryBucketMapper
    def self.call(action_plan:, categories:, bucket_ids: {})
      action_plan.with_lock do
        categories.each do |category|
          if category.routine_template.action_plan_id.present?
            if category.bucket&.action_plan_id != action_plan.id || (bucket_ids[category.id.to_s].present? && bucket_ids[category.id.to_s].to_i != category.bucket_id)
              raise ArgumentError, "As categorias do modelo correspondem aos buckets do próprio plano."
            end
            mapping = action_plan.routine_category_buckets.find_or_initialize_by(routine_category: category)
            mapping.update!(bucket: category.bucket)
            next
          end
          mapping = action_plan.routine_category_buckets.find_or_initialize_by(routine_category: category)
          selected_id = bucket_ids[category.id.to_s]

          mapping.bucket = if selected_id.present?
            action_plan.buckets.find(selected_id)
          elsif mapping.bucket.present? && !bucket_ids.key?(category.id.to_s)
            mapping.bucket
          else
            action_plan.buckets.find_by(name: category.name, inbox: false) ||
              action_plan.buckets.create!(name: category.name, position: action_plan.buckets.count)
          end

          mapping.save!
        end
      end
    end
  end
end
