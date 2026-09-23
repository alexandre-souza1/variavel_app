require "bigdecimal"

class MapaRemuneracaoService
  ZERO = BigDecimal("0")
  TWO = BigDecimal("2")
  DEVOLUTION_LIMIT = BigDecimal("0.03")

  def initialize(categoria)
    @categoria = categoria.to_s
    @rate_versions = CalculationRateVersion.where(categoria: [@categoria, 'geral']).order(:id).to_a.group_by { |rate| [rate.categoria, rate.nome] }
    @fallback_rates = ParametroCalculo.where(categoria: [@categoria, 'geral']).order(:id).to_a.group_by { |rate| [rate.categoria, rate.nome] }

  end

  def values(mapa)
    date = mapa.data_formatada
    raise EmployeeRole::HistoryError, "Mapa #{mapa.mapa}: data inválida." unless date
    valor_caixa = rate("valor_caixa", date)
    valor_entrega = rate("valor_entrega", date)
    valor_recarga = rate("valor_recarga", date)
    if mapa.fator == 2
      valor_cx = decimal(mapa.cx_real) * valor_caixa / TWO
      valor_pdv = decimal(mapa.pdv_real) * valor_entrega / TWO
    elsif @categoria == "motorista" && mapa.fator == 0 && decimal(mapa.pdv_total) >= TWO
      multiplicador = TWO
      valor_cx = decimal(mapa.cx_real) * valor_caixa * multiplicador
      valor_pdv = decimal(mapa.pdv_real) * valor_entrega * multiplicador
    else
      valor_cx = decimal(mapa.cx_real) * valor_caixa
      valor_pdv = decimal(mapa.pdv_real) * valor_entrega
    end

    valor_rec = recarga?(mapa) ? valor_recarga : ZERO
    valor_mp = recarga?(mapa) ? valor_rec : valor_cx + valor_pdv

    { valor_cx: valor_cx, valor_pdv: valor_pdv, valor_rec: valor_rec, valor_mp: valor_mp, categoria: @categoria, recarga: recarga?(mapa), recarga_inconsistente: @categoria == "van" && mapa.recarga == "SIM", tarifas: { caixa: valor_caixa, entrega: valor_entrega, recarga: valor_recarga } }
  end

  def totals(mapas)
    total_cx_real = ZERO
    total_pdv_real = ZERO
    total_pdv_total = ZERO
    total_valor = ZERO
    total_recargas = 0

    mapas.each do |mapa|
      recarga = recarga?(mapa)
      valores = values(mapa)

      unless recarga
        total_cx_real += decimal(mapa.cx_real)
        total_pdv_real += decimal(mapa.pdv_real)
        total_pdv_total += decimal(mapa.pdv_total)
      end

      total_recargas += 1 if recarga
      total_valor += valores[:valor_mp]
    end

    devolucoes = total_pdv_total - total_pdv_real
    percentual_devolucao = total_pdv_total.zero? ? ZERO : devolucoes / total_pdv_total
    @valor_bonus_devolucao = rate("bonus_devolucao", mapas.filter_map(&:data_formatada).max || Date.current, categoria: "geral")
    bonus_devolucao = mapas.size >= 15 && percentual_devolucao <= DEVOLUTION_LIMIT ? @valor_bonus_devolucao : ZERO

    {
      cx_real: total_cx_real,
      pdv_real: total_pdv_real,
      recargas: total_recargas,
      devolucoes: devolucoes,
      percentual_devolucao: percentual_devolucao,
      bonus_devolucao: bonus_devolucao,
      valor_total: total_valor + bonus_devolucao,
      valor_caixas: mapas.sum { |mapa| recarga?(mapa) ? ZERO : values(mapa)[:valor_cx] },
      valor_pdvs: mapas.sum { |mapa| recarga?(mapa) ? ZERO : values(mapa)[:valor_pdv] },
      valor_recargas: mapas.sum { |mapa| values(mapa)[:valor_rec] },
      quantidade_mapas: mapas.size,
      total_mapas: mapas.size
    }
  end

  private

  def recarga?(mapa)
    @categoria != "van" && mapa.recarga == "SIM"
  end

  def rate(nome, date, categoria: @categoria)
    versions = @rate_versions[[categoria, nome]] || []
    version = versions.select { |item| item.effective_on.nil? || item.effective_on <= date }.max_by { |item| [item.effective_on || Date.new(1), item.id] }
    decimal(versions.any? ? version&.valor : @fallback_rates[[categoria, nome]]&.first&.valor)
  end

  def decimal(value)
    return ZERO if value.nil? || value.to_s.strip.empty?

    BigDecimal(value.to_s)
  end
end
