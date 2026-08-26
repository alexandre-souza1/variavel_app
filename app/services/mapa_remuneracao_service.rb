require "bigdecimal"

class MapaRemuneracaoService
  ZERO = BigDecimal("0")
  TWO = BigDecimal("2")
  DEVOLUTION_LIMIT = BigDecimal("0.03")

  def initialize(categoria)
    @categoria = categoria.to_s
    @valor_caixa = decimal(ParametroCalculo.valor_para(categoria: @categoria, nome: "valor_caixa"))
    @valor_entrega = decimal(ParametroCalculo.valor_para(categoria: @categoria, nome: "valor_entrega"))
    @valor_recarga = decimal(ParametroCalculo.valor_para(categoria: @categoria, nome: "valor_recarga"))
    @valor_bonus_devolucao = decimal(ParametroCalculo.valor_para(categoria: "geral", nome: "bonus_devolucao"))
  end

  def values(mapa)
    if mapa.fator == 2
      valor_cx = decimal(mapa.cx_real) * @valor_caixa / TWO
      valor_pdv = decimal(mapa.pdv_real) * @valor_entrega / TWO
    elsif @categoria == "motorista" && mapa.fator == 0 && decimal(mapa.pdv_total) >= TWO
      multiplicador = TWO
      valor_cx = decimal(mapa.cx_real) * @valor_caixa * multiplicador
      valor_pdv = decimal(mapa.pdv_real) * @valor_entrega * multiplicador
    else
      valor_cx = decimal(mapa.cx_real) * @valor_caixa
      valor_pdv = decimal(mapa.pdv_real) * @valor_entrega
    end

    valor_rec = mapa.recarga == "SIM" ? @valor_recarga : ZERO
    valor_mp = mapa.recarga == "SIM" ? valor_rec : valor_cx + valor_pdv

    { valor_cx: valor_cx, valor_pdv: valor_pdv, valor_rec: valor_rec, valor_mp: valor_mp }
  end

  def totals(mapas)
    total_cx_real = ZERO
    total_pdv_real = ZERO
    total_pdv_total = ZERO
    total_valor = ZERO
    total_recargas = 0

    mapas.each do |mapa|
      recarga = mapa.recarga == "SIM"
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
    bonus_devolucao = mapas.size >= 15 && percentual_devolucao <= DEVOLUTION_LIMIT ? @valor_bonus_devolucao : ZERO

    {
      cx_real: total_cx_real,
      pdv_real: total_pdv_real,
      recargas: @categoria == "van" ? 0 : total_recargas,
      devolucoes: devolucoes,
      percentual_devolucao: percentual_devolucao,
      bonus_devolucao: @categoria == "van" ? ZERO : bonus_devolucao,
      valor_total: total_valor + (@categoria == "van" ? ZERO : bonus_devolucao),
      valor_caixas: mapas.sum { |mapa| mapa.recarga == "SIM" ? ZERO : values(mapa)[:valor_cx] },
      valor_pdvs: mapas.sum { |mapa| mapa.recarga == "SIM" ? ZERO : values(mapa)[:valor_pdv] },
      valor_recargas: @categoria == "van" ? ZERO : mapas.sum { |mapa| values(mapa)[:valor_rec] },
      quantidade_mapas: mapas.size,
      total_mapas: mapas.size
    }
  end

  private

  def decimal(value)
    return ZERO if value.nil? || value.to_s.strip.empty?

    BigDecimal(value.to_s)
  end
end
