class AzConsultasController < ApplicationController
  def index
  end

  def new
    @parametros = ParametroCalculo.all.group_by(&:categoria)
  end

  def show
    @matricula = params[:matricula]
    @turno = params[:turno].to_i
    @periodo_mes = params[:periodo_mes]

    if [0, 1, 2].include?(@turno)
      @operator = Operator.find_by(matricula: @matricula)

      if @operator
        # Filtra por turno E pelo mês selecionado
        @azmapas = AzMapa.where("? = ANY(turno)", @operator.turno)

        # Filtra por mês se existir
        if params[:periodo_mes].present?
          month = params[:periodo_mes].to_i
          start_date = Date.new(Date.today.year, month, 1)
          end_date = start_date.end_of_month

          @azmapas = @azmapas.where("EXTRACT(MONTH FROM data) = ?", month)
          @wms_tasks = WmsTask.where(operator_id: @operator.id)
                              .where(started_at: start_date..end_date)
                              .order(started_at: :desc)
        else
          @wms_tasks = WmsTask.none # Retorna uma relação vazia
        end

        # Carrega os parâmetros
        @valor_tma_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "valor_tma") || 0
        @valor_efc_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "valor_efc") || 0
        @valor_edf_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "valor_efd") || 0
        @valor_wms_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "tarefa_wms") || 0

        # Calcula o total de valor WMS (ajuste conforme sua regra de negócio)
        @total_valor_wms = @wms_tasks.sum(:duration) * @valor_wms_operator / 60.0
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
