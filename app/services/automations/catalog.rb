module Automations
  # Register supported connectors here. Rules store keys and data, never code,
  # SQL, arbitrary URLs or model-generated executable expressions.
  module Catalog
    SOURCES = {
      "invoices" => { label: "Financeiro", icon: "bi-wallet2", adapter: Sources::Invoices, operations: %w[sum average count] },
      "tasks" => { label: "Tarefas", icon: "bi-check2-square", adapter: Sources::Tasks, operations: %w[count] },
      "fleet" => { label: "Disponibilidade da frota", icon: "bi-truck", adapter: Sources::Fleet, operations: %w[count] }
    }.freeze
    ACTIONS = {
      "update_indicator" => { label: "Preencher indicador do GEROT", adapter: Actions::UpdateIndicator, icon: "bi-table" },
      "create_task" => { label: "Criar uma tarefa", adapter: Actions::CreateTask, icon: "bi-plus-square" },
      "notify" => { label: "Enviar aviso para mim", adapter: Actions::Notify, icon: "bi-bell" }
    }.freeze
    OPERATIONS = { "sum" => "Somar valores (R$)", "average" => "Média dos valores (R$)", "count" => "Contar registros" }.freeze

    def self.sources_for(user)
      return {} unless user&.active? && !user.mechanical?
      helper = Object.new.extend(NavbarHelper)
      SOURCES.select do |key, _|
        case key
        when "invoices" then helper.can_view_nav_link?(:finance, user)
        when "fleet" then helper.can_view_nav_link?(:availability, user)
        else true
        end
      end
    end
  end
end
