class ConsultasController < ApplicationController

  def index
  end

  def new
    @parametros = ParametroCalculo.all.group_by(&:categoria)
  end

  def show
    @matricula = params[:matricula]
    @categoria = params[:categoria]&.downcase

    @periodo_mes = params[:periodo_mes]

    if @categoria == "motorista"
      @driver = Driver.find_by(matricula: @matricula)

      if @driver
        normalized_name = @driver.nome.strip.gsub(/\s+/, " ")
        @fuel_consumption = FuelConsumption.where(driver_name: normalized_name).order(:created_at).last

        @mapas = Mapa.where(matric_motorista: @driver.promax)
        filtrar_por_periodo!

        @valor_caixa_motorista      = ParametroCalculo.valor_para(categoria: "motorista", nome: "valor_caixa")
        @valor_entrega_motorista    = ParametroCalculo.valor_para(categoria: "motorista", nome: "valor_entrega")
        @valor_recarga_motorista    = ParametroCalculo.valor_para(categoria: "motorista", nome: "valor_recarga")
        @valor_bonus_devolucao      = ParametroCalculo.valor_para(categoria: "geral", nome: "bonus_devolucao")

        definir_datas_periodo(@mapas)
      else
        flash.now[:alert] = "Matrícula não encontrada"
        render :new
      end

    elsif @categoria == "ajudante"
      @ajudante = Ajudante.find_by(matricula: @matricula)

      if @ajudante
        @mapas = Mapa.where(matric_ajudante: @ajudante.promax).or(Mapa.where(matric_ajudante_2: @ajudante.promax))
        filtrar_por_periodo!

        @valor_caixa_ajudante      = ParametroCalculo.valor_para(categoria: "ajudante", nome: "valor_caixa")
        @valor_entrega_ajudante    = ParametroCalculo.valor_para(categoria: "ajudante", nome: "valor_entrega")
        @valor_recarga_ajudante    = ParametroCalculo.valor_para(categoria: "ajudante", nome: "valor_recarga")
        @valor_bonus_devolucao     = ParametroCalculo.valor_para(categoria: "geral", nome: "bonus_devolucao")

        definir_datas_periodo(@mapas)
      else
        flash.now[:alert] = "Matrícula não encontrada"
        render :new
      end

    elsif @categoria == "van"
      @driver = Driver.find_by(matricula: @matricula, promax: 86)

      if @driver
        @mapas = Mapa.where(matric_motorista: @driver.promax)
        filtrar_por_periodo!

        @valor_caixa_van           = ParametroCalculo.valor_para(categoria: "van", nome: "valor_caixa")
        @valor_entrega_van         = ParametroCalculo.valor_para(categoria: "van", nome: "valor_entrega")
        @valor_bonus_devolucao     = ParametroCalculo.valor_para(categoria: "geral", nome: "bonus_devolucao")

        definir_datas_periodo(@mapas)
      else
        flash.now[:alert] = "Matrícula não encontrada"
        render :new
      end

    else
      flash.now[:alert] = "Categoria não reconhecida"
      render :new
    end

    prepare_report_totals! if @mapas && params[:periodo_mes].present?
  end

  private

  def filtrar_por_periodo!
    return unless params[:periodo_mes].present? && params[:periodo_ano].present?

    mes = params[:periodo_mes].to_i
    ano = params[:periodo_ano].to_i

    data_inicio = Date.new(ano, mes, 1).prev_month.change(day: 21)
    data_fim = Date.new(ano, mes, 20)

    @mapas = @mapas.select do |mapa|
      data = mapa.data_formatada
      data && data >= data_inicio && data <= data_fim
    end
  end

  def definir_datas_periodo(mapas)
    datas_validas = mapas.map(&:data_formatada).compact
    @data_inicio = datas_validas.min
    @data_fim = datas_validas.max
    @dias_periodo = (@data_fim - @data_inicio).to_i if @data_inicio && @data_fim
  end

  def prepare_report_totals!
    @mapa_totals = {
      caixas_reais: 0,
      valor_caixas: 0,
      pdvs_reais: 0,
      valor_pdvs: 0,
      recargas: 0,
      valor_recargas: 0,
      quantidade_mapas: @mapas.size,
      devolucoes: 0,
      percentual_devolucao: 0,
      bonus_devolucao: 0,
      total_mapas: 0,
      valor_total: 0
    }
    @mapa_calculations = {}

    total_pdv_real = @mapas.sum { |mapa| mapa.recarga == "SIM" ? 0 : mapa.pdv_real.to_f }
    total_pdv_total = @mapas.sum { |mapa| mapa.recarga == "SIM" ? 0 : mapa.pdv_total.to_f }
    percentual_devolucao = total_pdv_total.zero? ? 0 : (total_pdv_total - total_pdv_real) / total_pdv_total

    @mapas.each do |mapa|
      valor_cx, valor_pdv, valor_rec = mapa_values(mapa)
      valor_mp = mapa.recarga == "SIM" ? valor_rec : valor_cx + valor_pdv
      @mapa_calculations[mapa.id] = { valor_cx: valor_cx, valor_pdv: valor_pdv, valor_rec: valor_rec, valor_mp: valor_mp }

      unless mapa.recarga == "SIM"
        @mapa_totals[:caixas_reais] += mapa.cx_real.to_f
        @mapa_totals[:valor_caixas] += valor_cx
        @mapa_totals[:pdvs_reais] += mapa.pdv_real.to_f
        @mapa_totals[:valor_pdvs] += valor_pdv
      end

      unless @categoria == "van"
        @mapa_totals[:recargas] += 1 if mapa.recarga == "SIM"
        @mapa_totals[:valor_recargas] += valor_rec
      end

      @mapa_totals[:total_mapas] += 1
      @mapa_totals[:valor_total] += valor_mp
    end

    @mapa_totals[:devolucoes] = total_pdv_total - total_pdv_real
    @mapa_totals[:percentual_devolucao] = percentual_devolucao
    @mapa_totals[:bonus_devolucao] = if @mapas.size >= 15 && percentual_devolucao <= 0.03
                                      @valor_bonus_devolucao.to_f
                                    else
                                      0
                                    end
    @mapa_totals[:valor_total] += @mapa_totals[:bonus_devolucao]
  end

  def mapa_values(mapa)
    case @categoria
    when "motorista"
      if mapa.fator == 2
        valor_cx = mapa.cx_real.to_f * @valor_caixa_motorista.to_f / 2
        valor_pdv = mapa.pdv_real.to_f * @valor_entrega_motorista.to_f / 2
      else
        multiplicador = mapa.fator == 0 && mapa.pdv_total.to_f >= 2 ? 2 : 1
        valor_cx = mapa.cx_real.to_f * @valor_caixa_motorista.to_f * multiplicador
        valor_pdv = mapa.pdv_real.to_f * @valor_entrega_motorista.to_f * multiplicador
      end
      valor_rec = mapa.recarga == "SIM" ? @valor_recarga_motorista.to_f : 0
    when "ajudante"
      divisor = mapa.fator == 2 ? 2 : 1
      valor_cx = mapa.cx_real.to_f * @valor_caixa_ajudante.to_f / divisor
      valor_pdv = mapa.pdv_real.to_f * @valor_entrega_ajudante.to_f / divisor
      valor_rec = mapa.recarga == "SIM" ? @valor_recarga_ajudante.to_f : 0
    when "van"
      valor_cx = mapa.cx_real.to_f * @valor_caixa_van.to_f
      valor_pdv = mapa.pdv_real.to_f * @valor_entrega_van.to_f
      valor_rec = 0
    else
      valor_cx = valor_pdv = valor_rec = 0
    end

    [valor_cx, valor_pdv, valor_rec]
  end
end
