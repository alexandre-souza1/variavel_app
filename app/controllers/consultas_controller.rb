class ConsultasController < ApplicationController

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
        @mapas = Mapa.where(matric_ajudante: @ajudante.promax)
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
end
