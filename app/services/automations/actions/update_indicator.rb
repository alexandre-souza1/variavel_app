module Automations
  module Actions
    class UpdateIndicator
      def self.validate!(rule)
        Configuration.check_keys!(rule.action_config, %w[routine_template_id routine_indicator_id overwrite_manual])
        template = RoutineTemplate.visible_to(rule.user).find_by(id: rule.action_config["routine_template_id"])
        indicator = RoutineIndicator.active.find_by(id: rule.action_config["routine_indicator_id"])
        unless template && indicator && indicator.routine_category.routine_template_id == template.id
          raise Invalid, "Selecione um modelo e um indicador ativo disponíveis para o responsável."
        end
        expected = Period.new(rule.period).frequency
        raise Invalid, "O período consultado deve acompanhar a frequência do indicador: dia, semana ou mês." unless expected == indicator.response_frequency
        types = rule.operation == "count" ? %w[integer decimal] : %w[currency decimal]
        raise Invalid, "Contagens exigem indicador inteiro ou decimal; valores financeiros exigem moeda ou decimal." unless types.include?(indicator.value_type)
      end

      def self.preview(rule, period:, result:)
        routines = Routine.visible_to(rule.user).open.where(routine_template_id: rule.action_config["routine_template_id"])
          .where("period_start <= ? AND period_end >= ?", period.anchor, period.anchor).limit(2).to_a
        raise Invalid, "Nenhum GEROT aberto do modelo cobre a data-base #{I18n.l(period.anchor)}." if routines.empty?
        raise Invalid, "Mais de um GEROT aberto cobre a data-base. Resolva os períodos sobrepostos." if routines.size > 1
        routine = routines.first
        indicator = RoutineIndicator.find(rule.action_config["routine_indicator_id"])
        raise Invalid, "Este indicador não está selecionado no GEROT aberto." unless routine.selected_indicator_ids.include?(indicator.id)
        reference = routine.reference_dates_for(indicator).find { |date| period.include_reference?(date) }
        raise Invalid, "O GEROT não possui uma célula de referência neste período." unless reference
        target = routine.routine_values.find_by(routine_indicator_id: indicator.id, reference_date: reference)
        protected = target&.value.present? &&
          (target.automation_rule_id.present? ? target.automation_rule_id != rule.id : rule.action_config["overwrite_manual"] != "1")
        { label: "#{routine.title} / #{indicator.name}", routine_id: routine.id, indicator_id: indicator.id,
          reference_date: reference, previous_value: target&.value, protected: protected,
          path: Rails.application.routes.url_helpers.routine_path(routine) }
      end

      def self.execute!(rule, period:, result:, now:)
        destination = preview(rule, period: period, result: result)
        routine = Routine.lock.find(destination[:routine_id])
        raise Invalid, "Este GEROT não aceita mais preenchimentos." unless routine.open?
        target = routine.routine_values.create_or_find_by!(routine_indicator_id: destination[:indicator_id], reference_date: destination[:reference_date])
        target.lock!
        destination = preview(rule, period: period, result: result)
        return { status: "skipped", message: "Preenchimento protegido: o valor atual foi preservado.", destination: destination } if destination[:protected]
        value = rule.operation == "count" ? result[:value].to_i.to_s : result[:value].to_s("F")
        if target.value.present? && target.value.to_d == value.to_d
          return { status: "unchanged", message: "O indicador já possui o valor calculado.", destination: destination }
        end
        previous = target.value
        target.update!(value: value, updated_by: rule.user, automation_rule: rule)
        routine.routine_activities.create!(user: rule.user, routine_value: target, activity_type: :value_changed,
          previous_value: previous, new_value: value, metadata: { source: "automation", automation_rule_id: rule.id, automation_name: rule.name })
        Routines::DeviationTaskGenerator.call(routine_value: target, actor: rule.user, previous_value: previous)
        { status: "success", message: "Indicador atualizado.", destination: destination.merge(value: value) }
      end
    end
  end
end
