class ConsultasController < ApplicationController
  def new
  end

  def show
    @matricula = params[:matricula]
    @categoria = params[:categoria]&.downcase # Recebe a categoria enviada pelo formulário

    if @categoria == "motorista"
      @driver = Driver.find_by(matricula: @matricula)

      if @driver
        @mapas = Mapa.where(matric_motorista: @driver.promax)

        @valor_caixa   = ParametroCalculo.find_by(nome: ParametroCalculo::NOME_VALOR_CAIXA)&.valor
        @valor_entrega = ParametroCalculo.find_by(nome: ParametroCalculo::NOME_VALOR_ENTREGA)&.valor
        @valor_recarga = ParametroCalculo.find_by(nome: ParametroCalculo::NOME_VALOR_RECARGA)&.valor
        @valor_bonus_devolucao = ParametroCalculo.find_by(nome: ParametroCalculo::NOME_VALOR_BONUS_DEVOLUCAO)&.valor

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

        @valor_caixa_ajudante   = ParametroCalculo.find_by(nome: ParametroCalculo::NOME_VALOR_CAIXA_AJUDANTE)&.valor
        @valor_entrega_ajudante = ParametroCalculo.find_by(nome: ParametroCalculo::NOME_VALOR_ENTREGA_AJUDANTE)&.valor
        @valor_recarga_ajudante = ParametroCalculo.find_by(nome: ParametroCalculo::NOME_VALOR_RECARGA_AJUDANTE)&.valor
        @valor_bonus_devolucao = ParametroCalculo.find_by(nome: ParametroCalculo::NOME_VALOR_BONUS_DEVOLUCAO)&.valor

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
