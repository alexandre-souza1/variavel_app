module Routines
  class PlanTemplateBuilder
    def self.call(action_plan:, attributes: {})
      action_plan.with_lock do
        template = RoutineTemplate.find_by(action_plan_id: action_plan.id)
        next template if template

        default_name = "GEROT — #{action_plan.name}"
        default_name += " (Plano #{action_plan.id})" if RoutineTemplate.exists?(name: default_name)
        action_plan.create_gerot_template!({ name: default_name, sector: action_plan.sector }.merge(attributes.symbolize_keys.except(:action_plan_id, :sector)))
      end
    end
  end
end
