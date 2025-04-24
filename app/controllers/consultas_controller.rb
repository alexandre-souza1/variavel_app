class ConsultasController < ApplicationController

  def new
    @parametros = ParametroCalculo.all.group_by(&:categoria)
  end

  def show
    @matricula = params[:matricula]
    @categoria = params[:categoria]&.downcase # Recebe a categoria enviada pelo formulário

    if @categoria == "motorista"
      @driver = Driver.find_by(matricula: @matricula)

      if @driver
        @mapas = Mapa.where(matric_motorista: @driver.promax)

        @valor_caixa_motorista      = ParametroCalculo.valor_para(categoria: "motorista", nome: "valor_caixa")
        @valor_entrega_motorista    = ParametroCalculo.valor_para(categoria: "motorista", nome: "valor_entrega")
        @valor_recarga_motorista    = ParametroCalculo.valor_para(categoria: "motorista", nome: "valor_recarga")
        @valor_bonus_devolucao  = ParametroCalculo.valor_para(categoria: "geral", nome: "bonus_devolucao")

        # Extrair datas válidas e converter
        datas_validas = @mapas.map do |mapa|
          if mapa.data.present? && mapa.data.match?(/^\d{8}$/)
            begin
              Date.strptime(mapa.data, "%d%m%Y")
            rescue
              nil
            end
          end
        end.compact

        @data_inicio = datas_validas.min
        @data_fim = datas_validas.max
        @dias_periodo = (@data_fim - @data_inicio).to_i if @data_inicio && @data_fim
      else
        flash.now[:alert] = "Matrícula não encontrada"
        render :new
      end

    elsif @categoria == "ajudante"
      @ajudante = Ajudante.find_by(matricula: @matricula)

      if @ajudante
        @mapas = Mapa.where(matric_ajudante: @ajudante.promax)

        @valor_caixa_ajudante      = ParametroCalculo.valor_para(categoria: "ajudante", nome: "valor_caixa")
        @valor_entrega_ajudante    = ParametroCalculo.valor_para(categoria: "ajudante", nome: "valor_entrega")
        @valor_recarga_ajudante    = ParametroCalculo.valor_para(categoria: "ajudante", nome: "valor_recarga")
        @valor_bonus_devolucao  = ParametroCalculo.valor_para(categoria: "geral", nome: "bonus_devolucao")

        # Extrair datas válidas e converter
        datas_validas = @mapas.map do |mapa|
          if mapa.data.present? && mapa.data.match?(/^\d{8}$/)
            begin
              Date.strptime(mapa.data, "%d%m%Y")
            rescue
              nil
            end
          end
        end.compact

        @data_inicio = datas_validas.min
        @data_fim = datas_validas.max
        @dias_periodo = (@data_fim - @data_inicio).to_i if @data_inicio && @data_fim
      else
        flash.now[:alert] = "Matrícula não encontrada"
        render :new
      end
    elsif @categoria == "van"
      # TODO: substituir promax: 86 por van: true quando coluna estiver disponível
      @driver = Driver.find_by(matricula: @matricula, promax: 86)

      if @driver
        @mapas = Mapa.where(matric_motorista: @driver.promax)

        @valor_caixa_van      = ParametroCalculo.valor_para(categoria: "van", nome: "valor_caixa")
        @valor_entrega_van    = ParametroCalculo.valor_para(categoria: "van", nome: "valor_entrega")
        @valor_bonus_devolucao  = ParametroCalculo.valor_para(categoria: "geral", nome: "bonus_devolucao")

        # Extrair datas válidas e converter
        datas_validas = @mapas.map do |mapa|
          if mapa.data.present? && mapa.data.match?(/^\d{8}$/)
            begin
              Date.strptime(mapa.data, "%d%m%Y")
            rescue
              nil
            end
          end
        end.compact

        @data_inicio = datas_validas.min
        @data_fim = datas_validas.max
        @dias_periodo = (@data_fim - @data_inicio).to_i if @data_inicio && @data_fim
      else
        flash.now[:alert] = "Matrícula não encontrada"
        render :new
      end
    else
      flash.now[:alert] = "Categoria não reconhecida"
      render :new
    end
  end
end
