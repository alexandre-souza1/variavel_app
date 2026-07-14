module MapasHelper
  def nome_mes_ano(ano, mes)
    I18n.l(Date.new(ano, mes, 1), format: :mes_ano)
  end
end
