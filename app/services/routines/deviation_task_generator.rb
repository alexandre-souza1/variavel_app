module Routines
  class DeviationTaskGenerator
    def self.call(routine_value:, actor:, previous_value: nil, comment: nil)
      RoutineValue.transaction do
        routine_value = RoutineValue.lock.find(routine_value.id)
        routine = routine_value.routine
        next unless routine.action_plan.present? && routine.open?

        indicator = routine_value.routine_indicator
        goal = indicator.target_for(routine_value.reference_date)&.goal
        status = GoalEvaluation.call(indicator: indicator, value: routine_value.value, goal: goal)

        if (task = routine_value.generated_task)
          if comment
            task.comments.create!(user: actor, content: comment.body)
          else
            TaskActivityService.log(
              task: task, user: actor, activity_type: :routine_value_changed,
              old_value: previous_value, new_value: routine_value.value,
              metadata: { reference_date: routine_value.reference_date, goal: goal, status: status }
            )
          end
          next task
        end
        next unless status == :danger
        next unless routine.task_generation_deviation? || comment&.body.present?

        bucket = indicator.routine_category.bucket || routine.action_plan.routine_category_buckets.find_by!(routine_category: indicator.routine_category).bucket
        task = bucket.tasks.create!(
          routine_value: routine_value,
          creator: actor,
          title: "Investigar #{indicator.name} fora da meta — #{routine_value.reference_date.strftime('%d/%m/%Y')}",
          description: [
            "Gerado pelo GEROT: #{routine.title}",
            "Categoria: #{indicator.routine_category.name}",
            "Indicador: #{indicator.name}",
            "Data de referência: #{routine_value.reference_date.strftime('%d/%m/%Y')}",
            "Valor registrado: #{routine_value.value}",
            "Meta: #{indicator.less_or_equal? ? 'menor ou igual a' : 'maior ou igual a'} #{goal}",
            ("Comentário: #{comment.body}" if comment)
          ].compact.join("\n")
        )
        task.comments.create!(user: actor, content: comment.body) if comment
        TaskActivityService.log(task: task, user: actor, activity_type: :created)
        task
      end
    end
  end
end
