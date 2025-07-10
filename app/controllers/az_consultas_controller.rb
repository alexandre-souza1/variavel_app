class AzConsultasController < ApplicationController
  def index
  end

  def new
    @parametros = ParametroCalculo.all.group_by(&:categoria)
  end

  def show
    @matricula = params[:matricula]
    @turno = params[:turno].to_i  # Garante que é um inteiro

    if [0, 1, 2].include?(@turno)
      @operator = Operator.find_by(matricula: @matricula)

      if @operator
        # CORREÇÃO AQUI - usando ANY para filtrar em array
        @azmapas = AzMapa.where("? = ANY(turno)", @operator.turno)

        # Carrega os parâmetros conforme o turno
        if @turno == 1
          @valor_edf_operator = ParametroCalculo.valor_para(categoria: "operator", nome: "valor_efd")
        else
          @valor_tma_operator = ParametroCalculo.valor_para(categoria: "operator", nome: "valor_tma")
          @valor_efc_operator = ParametroCalculo.valor_para(categoria: "operator", nome: "valor_efc")
        end

        @valor_wms_operator = ParametroCalculo.valor_para(categoria: "operator", nome: "tarefa_wms")
      else
        flash.now[:alert] = "Matrícula não encontrada"
        render :new
      end
    else
      flash.now[:alert] = "Turno inválido"
      render :new
    end
  end

  private
  # métodos privados se necessário
end
