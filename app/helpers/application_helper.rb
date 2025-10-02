module ApplicationHelper
  # Retorna um hash com os registros paginados e informações de paginação
  def paginate_records(relation, params, per_page: 15)
    current_page = (params[:page] || 1).to_i
    total_pages = (relation.count / per_page.to_f).ceil

    records = relation.offset((current_page - 1) * per_page).limit(per_page)

    {
      records: records,
      current_page: current_page,
      total_pages: total_pages,
      per_page: per_page
    }
  end

  def category_color(budget_category)
    # Mapeia cores baseadas no setor ou nome da categoria
    colors = {
      'combustivel' => 'warning',
      'manutencao' => 'info',
      'pecas' => 'success',
      'seguro' => 'danger',
      'outros' => 'secondary'
    }

    # Tenta pelo setor primeiro, depois pelo nome
    color_key = budget_category.sector.downcase
    colors[color_key] || 'primary'
  end

  def category_icon(budget_category)
  # Mapeia ícones baseados no setor ou nome da categoria
  icons = {
    'combustivel' => 'gas-pump',
    'manutencao' => 'tools',
    'pecas' => 'cog',
    'seguro' => 'shield-alt',
    'outros' => 'tag'
  }

  # Tenta pelo setor primeiro, depois pelo nome
  icon_key = budget_category.sector.downcase
  icons[icon_key] || 'tag'
end
end
