module DownloadsHelper
  def category_icon(category)
    case category
    when 'padroes' then 'fas fa-book'
    when 'matrizes' then 'fas fa-table'
    when 'lups' then 'fas fa-lightbulb'
    else 'fas fa-file'
    end
  end

  def category_title(category)
    case category
    when 'padroes' then 'Padrões Operacionais'
    when 'matrizes' then 'Matrizes de Controle'
    when 'lups' then 'Lições de Um Ponto (LUPs)'
    else category.humanize
    end
  end
end
