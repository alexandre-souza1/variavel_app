class AzConsultasController < ApplicationController
  def index
  end

  def new
    @parametros = ParametroCalculo.all.group_by(&:categoria)
  end

def show
  @matricula = params[:matricula]
  @turno = params[:turno].to_i
  @periodo_mes = params[:periodo_mes] # Adicione esta linha

  if [0, 1, 2].include?(@turno)
    @operator = Operator.find_by(matricula: @matricula)

    if @operator
      # Filtra por turno E pelo mês selecionado
      @azmapas = AzMapa.where("? = ANY(turno)", @operator.turno)

      # Adicione este filtro por mês
      if params[:periodo_mes].present?
        @azmapas = @azmapas.where("EXTRACT(MONTH FROM data) = ?", params[:periodo_mes])
      end

      # Carrega os parâmetros
      @valor_tma_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "valor_tma") || 0
      @valor_efc_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "valor_efc") || 0
      @valor_edf_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "valor_efd") || 0
      @valor_wms_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "tarefa_wms") || 0
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
