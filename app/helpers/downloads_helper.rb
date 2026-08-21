module DownloadsHelper
  def category_icon(category)
    case category
    when "padrao" then "bi bi-file-text"
    when "lup" then "bi bi-file-check"
    when "manual" then "bi bi-book"
    when "matriz" then "bi bi-diagram-3"
    else "bi bi-file-earmark"
    end
  end

  def category_title(category)
    case category
    when "padrao" then "Padrões Operacionais"
    when "matriz" then "Matrizes de Controle"
    when "lup" then "Lições de Um Ponto (LUPs)"
    when "manual" then "Manuais"
    else category.humanize
    end
  end
end
