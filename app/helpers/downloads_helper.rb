module DownloadsHelper

  def category_icon(category)
    case category
    when "PADRÃO"
      "bi bi-file-text"
    when "LUP"
      "bi bi-file-check"
    when "MATRIZ"
      "bi bi-diagram-3"
    else
      "bi bi-file-earmark"
    end
  end

  def category_title(category)
    case category
    when "PADRÃO"
      "Padrões Operacionais"
    when "MATRIZ"
      "Matrizes de Controle"
    when "LUP"
      "Lições de Um Ponto (LUPs)"
    else
      category.humanize
    end
  end

  def download_url(download)
    open_download_url(download)
  end

end
