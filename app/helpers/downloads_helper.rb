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

  def sector_title(sector)
    {
      "FROTA" => "Frota",
      "ENTREGA" => "Distribuição",
      "ARMAZEM" => "Armazém",
      "RH" => "RH",
      "FINANCEIRO" => "Financeiro",
      "SEGURANÇA" => "Segurança"
    }.fetch(sector, sector.to_s.humanize)
  end

  def sector_icon(sector)
    {
      "FROTA" => "bi bi-truck",
      "ENTREGA" => "bi bi-box-seam",
      "ARMAZEM" => "bi bi-building",
      "RH" => "bi bi-people",
      "FINANCEIRO" => "bi bi-cash-stack",
      "SEGURANÇA" => "bi bi-shield-check"
    }.fetch(sector, "bi bi-diagram-3")
  end

end
