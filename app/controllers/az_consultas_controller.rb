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
        # Carrega os parâmetros
        @valor_tma_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "valor_tma") || 0
        @valor_efc_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "valor_efc") || 0
        @valor_efd_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "valor_efd") || 0
        @valor_wms_operator = ParametroCalculo.valor_para(categoria: "operador", nome: "tarefa_wms") || 0

        # Filtra por turno E pelo mês selecionado
        @azmapas = AzMapa.where("? = ANY(turno)", @operator.turno)

        # Filtra por mês se existir
        if params[:periodo_mes].present?
          mes = params[:periodo_mes].to_i
          ano = params[:periodo_ano].to_i
          start_date = Date.new(ano, mes, 1).prev_month.change(day: 19)
          end_date = Date.new(ano, mes, 18)

          @azmapas = @azmapas.where(data: start_date..end_date)
          # Paginação manual
          all_tasks = WmsTask.where(operator_id: @operator.id)
                            .where(started_at: start_date..end_date)
                            .order(started_at: :desc)

          # Calcula o total de valor WMS **antes da paginação**
          @total_wms = all_tasks.sum { |t| (t.duration.to_f * 60) >= 10 ? @valor_wms_operator : 0 }

          pagination = helpers.paginate_records(all_tasks, params, per_page: 15)

          @wms_tasks = pagination[:records]
          @current_page = pagination[:current_page]
          @total_pages = pagination[:total_pages]

          definir_datas_periodo(@azmapas)
        else
          @wms_tasks = WmsTask.none # Retorna uma relação vazia
          @total_wms = 0
        end
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


  def definir_datas_periodo(azmapas)
    # seleciona apenas a coluna data
    datas = azmapas.pluck(:data)

    @data_inicio = datas.min
    @data_fim = datas.max
    @dias_periodo = (@data_fim - @data_inicio).to_i if @data_inicio && @data_fim
  end
end
