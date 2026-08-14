# app/helpers/navbar_helper.rb
module NavbarHelper
  NAVBAR_LINKS = {
    tasks: {
      path: :action_plans_path,
      icon: 'bi-bar-chart-fill',
      label: 'Tarefas',
      sectors: [:fleet, :warehouse, :hr, :finance, :planning, :du, :safety]
    },
    availability: {
      path: :fleet_availabilities_path,
      icon: 'bi-truck',
      label: 'Disponibilidade',
      sectors: [:fleet, :du]
    },
    gerot: {
      path: :routines_path,
      icon: 'bi-kanban',
      label: 'GEROT',
      sectors: [:fleet, :du, :warehouse, :hr, :finance, :planning, :safety]
    },
    stress_test: {
      path: :placas_por_setor_path,
      icon: 'bi-speedometer2',
      label: 'Stress Test',
      sectors: [:fleet, :safety]
    },
    finance: {
      path: :invoices_path,
      icon: 'bi-coin',
      label: 'Financeiro',
      sectors: [:fleet, :hr, :finance, :planning, :safety]
    },
    du: {
      path: :variaveis_path,
      icon: 'bi-cash-stack',
      label: 'Variáveis',
      sectors: [:du, :hr, :safety]
    }
  }

  REGISTRATION_SUBITEMS = {
    cost_centers: {
      label: 'Centros de Custo',
      path: :admin_cost_centers_path,
      sectors: [:fleet, :finance, :planning, :safety],
      group: 'Finanças'
    },
    budget_categories: {
      label: 'Categorias',
      path: :admin_budget_categories_path,
      sectors: [:fleet, :finance, :planning, :safety],
      group: 'Finanças'
    },
    suppliers: {
      label: 'Fornecedores',
      path: :suppliers_path,
      sectors: [:fleet, :finance, :planning, :safety],
      group: 'Finanças'
    },
    drivers: {
      label: 'Motoristas',
      path: :drivers_path,
      sectors: [:du, :hr, :safety],
      group: 'DU'
    },
    ajudantes: {
      label: 'Ajudantes',
      path: :ajudantes_path,
      sectors: [:du, :hr, :safety],
      group: 'DU'
    },
    operators: {
      label: 'Operadores',
      path: :operators_path,
      sectors: [:warehouse, :hr, :safety],
      group: 'AZ'
    },
    az_ajudantes: {
      label: 'Ajudantes AZ',
      path: :az_ajudantes_path,
      sectors: [:warehouse, :hr, :safety],
      group: 'AZ'
    },
    plates: {
      label: 'Placas',
      path: :plates_path,
      sectors: [:fleet, :du],
      group: 'Geral'
    },
    fleet_availability_email_setting: {
      label: 'E-mail da disponibilidade',
      path: :edit_fleet_availability_email_setting_path,
      sectors: [:fleet],
      group: 'Geral'
    },
    routine_templates: {
      label: 'Modelos de Gerot',
      path: :routine_templates_path,
      sectors: [:fleet, :du, :warehouse, :hr, :finance, :planning, :safety],
      group: 'Geral'
    },
    action_plans: {
      label: 'Planos de Ação',
      path: :action_plans_path,
      sectors: [:fleet, :du, :warehouse, :hr, :finance, :planning, :safety],
      group: 'Geral'
    }
  }

  # Ordem de exibição dos grupos (caso queira personalizar)
  GROUP_ORDER = ['Finanças', 'DU', 'AZ', 'Geral'].freeze

  # Apenas admin vê tudo; supervisor e usuários comuns seguem as regras do setor
  def can_view_nav_link?(link_key, user)
    return true if user.admin?
    link = NAVBAR_LINKS[link_key]
    return false unless link
    link[:sectors].include?(user.sector&.to_sym)
  end

  def can_view_subitem?(subitem_key, user)
    return true if user.admin?
    subitem = REGISTRATION_SUBITEMS[subitem_key]
    return false unless subitem
    subitem[:sectors].include?(user.sector&.to_sym)
  end

  def can_view_registration_dropdown?(user)
    return true if user.admin?
    REGISTRATION_SUBITEMS.any? { |key, _| can_view_subitem?(key, user) }
  end

  # Menus DU e AZ: aparecem apenas para admin ou para quem tem o setor correspondente
  def can_view_du_menu?(user)
    return true if user.admin?
    user.sector.to_sym == :du
  end

  def can_view_az_menu?(user)
    return true if user.admin?
    user.sector.to_sym == :warehouse
  end
end
