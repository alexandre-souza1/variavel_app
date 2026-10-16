module Automations
  module Sources
    class Invoices
      def self.validate!(rule)
        Configuration.check_keys!(rule.filters, %w[budget_category_id budget_category_ids sector])
        ids = Configuration.category_ids(rule.filters)
        categories = Configuration.categories_for(rule.user)
        if ids.any? && categories.where(id: ids).count != ids.size
          raise Invalid, "Uma ou mais categorias financeiras estão indisponíveis para o responsável."
        end
        if rule.filters["sector"].present?
          allowed = rule.user.admin? || rule.user.sector_finance? ? BudgetCategory.sectors.keys : rule.user.budget_sectors
          raise Invalid, "Setor financeiro indisponível." unless allowed.include?(rule.filters["sector"])
          if ids.any? && categories.where(sector: rule.filters["sector"], id: ids).count != ids.size
            raise Invalid, "Todas as categorias devem pertencer ao setor escolhido."
          end
        end
      end

      def self.call(rule, period:, now:)
        scope = Invoice.visible_to(rule.user).where(date_issued: period.date_range)
        ids = Configuration.category_ids(rule.filters)
        scope = scope.where(budget_category_id: ids) if ids.any?
        scope = scope.where(budget_category_id: BudgetCategory.where(sector: rule.filters["sector"]).select(:id)) if rule.filters["sector"].present?
        count = scope.count
        value = case rule.operation
        when "sum" then scope.sum(:total).to_d.round(2)
        when "average" then scope.average(:total).to_d.round(2)
        when "count" then count
        end
        { value: value.to_d, count: count, available: count.positive?, note: "Lançamentos por data de emissão; não representam confirmação de pagamento." }
      end
    end
  end
end
