module Automations
  module Configuration
    def self.validate!(rule)
      raise Invalid, "O responsável precisa estar ativo e ter acesso ao módulo." unless rule.user&.active? && !rule.user.mechanical?
      source = Catalog.sources_for(rule.user)[rule.source_key]
      raise Invalid, "Origem indisponível para este usuário." unless source
      raise Invalid, "Escolha um cálculo compatível com a origem." unless source[:operations].include?(rule.operation)
      raise Invalid, "Escolha um período válido." unless Period::LABELS.key?(rule.period)
      raise Invalid, "Configuração inválida." unless rule.filters.is_a?(Hash) && rule.action_config.is_a?(Hash)
      source[:adapter].validate!(rule)
      action = Catalog::ACTIONS[rule.action_key]
      raise Invalid, "Escolha uma ação disponível." unless action
      action[:adapter].validate!(rule)
    end

    def self.categories_for(user)
      return BudgetCategory.none unless user&.active? && !user.mechanical?
      user.admin? || user.sector_finance? ? BudgetCategory.all : BudgetCategory.where(sector: user.budget_sectors)
    end

    # JSON rules and older AI proposals may still carry the singular key.
    # A present empty list explicitly means all permitted categories.
    def self.category_ids(filters)
      if filters.key?("budget_category_ids")
        raw = filters["budget_category_ids"]
        raise Invalid, "Selecione as categorias em uma lista." unless raw.is_a?(Array)
        raise Invalid, "Informe a lista de categorias sem combinar com o filtro antigo." if filters["budget_category_id"].present?
      else
        raw = filters["budget_category_id"].present? ? [filters["budget_category_id"]] : []
      end
      raw = raw.reject { |value| value == "" }
      raise Invalid, "Selecione até 200 categorias por regra." if raw.size > 200
      ids = raw.map do |value|
        unless (value.is_a?(Integer) || value.is_a?(String)) && value.to_s.match?(/\A[0-9]+\z/) && value.to_i.positive?
          raise Invalid, "Uma categoria selecionada é inválida."
        end
        value.to_i
      end
      ids.uniq.sort.map(&:to_s)
    end

    def self.buckets_for(user)
      Bucket.work.where(action_plan_id: ActionPlan.visible_to(user).select(:id))
    end

    def self.check_keys!(hash, keys)
      raise Invalid, "A configuração contém campos indisponíveis." if (hash.keys - keys).any?
    end
  end
end
