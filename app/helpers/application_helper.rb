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

  def category_color(category)
  colors = {
    'combustivel' => 'warning',
    'manutencao' => 'info',
    'pecas' => 'success',
    'seguro' => 'danger',
    'outros' => 'secondary'
  }
  colors[category.downcase] || 'primary'
end
end
