class DashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_mes_ano, only: [:index, :placas_por_setor]

  def index
    # ------------------------------------------------------------
    # 1. Tarefas
    # ------------------------------------------------------------
    @pending_tasks = Task.includes(bucket: :action_plan)
                         .where(completed: [false, nil])
                         .where(assignee_id: current_user.id)

    @tasks_due_soon = Task.where(completed: [false, nil])
                          .where("due_at <= ?", 2.days.from_now.end_of_day)
                          .where(assignee_id: current_user.id)
                          .order(due_at: :asc)
                          .limit(5)

    # ------------------------------------------------------------
    # 2. Custos – com filtro por categoria (dropdown)
    # ------------------------------------------------------------
    # Período: mês atual
    month_start = Date.current.beginning_of_month
    month_end   = Date.current.end_of_month
    month_scope = Invoice.where(date_issued: month_start..month_end)

    # Cards
    @current_month_cost = month_scope.sum(:total)
    @total_invoices     = month_scope.count

    # Gastos por categoria (gráfico donut) – mês atual
    @expenses_by_category = month_scope
      .joins(:budget_category)
      .group('budget_categories.name')
      .sum(:total)
      .transform_values { |v| v.to_f.round(2) }

    # ------------------------------------------------------------
    # Filtro por categoria para o gráfico de evolução
    # ------------------------------------------------------------
    @selected_category_id = params[:category_id].to_i if params[:category_id].present?

    # Evolução mensal (últimos 12 meses)
    monthly_totals = Invoice
      .where(date_issued: 11.months.ago.beginning_of_month..Date.current.end_of_month)

    # Aplica filtro por categoria se selecionado
    if @selected_category_id.present?
      monthly_totals = monthly_totals.where(budget_category_id: @selected_category_id)
    end

    monthly_totals = monthly_totals
      .group("DATE_TRUNC('month', date_issued)")
      .sum(:total)

    # Ordena do mês mais antigo para o mais recente e formata para o Chartkick
    @monthly_costs = monthly_totals
      .sort_by { |month, _| month }
      .map { |month, total| [month.strftime("%b %Y"), total.to_f] }

    # ------------------------------------------------------------
    # Lista de categorias para o dropdown (apenas as que têm invoices)
    # ------------------------------------------------------------
    @categories = BudgetCategory
      .joins(:invoices)
      .where(invoices: { date_issued: 11.months.ago.beginning_of_month..Date.current.end_of_month })
      .distinct
      .order(:name)

    # ------------------------------------------------------------
    # 3. Métricas de frotas ROTA
    # ------------------------------------------------------------
    @total_vehicles = Plate.where(setor: "ROTA").count
    @vehicles_by_type = Plate.where(setor: "ROTA").group(:tipo).count
    @vehicles_not_used_this_month = vehicles_not_used_in_month(@mes, @ano, "ROTA")

    # ------------------------------------------------------------
    # 4. Último mapa (baseado no campo 'data' – string DDMMYYYY)
    # ------------------------------------------------------------
    @last_map_date = Mapa
      .where.not(data: [nil, ""])
      .pluck(:data)
      .filter_map do |data|
        numeros = data.to_s.gsub(/\D/, "")

        begin
          case numeros.length
          when 8
            Date.strptime(numeros, "%d%m%Y")
          when 7
            Date.new(
              numeros[3,4].to_i,
              numeros[1,2].to_i,
              numeros[0,1].to_i
            )
          else
            nil
          end
        rescue
          nil
        end
      end
      .max

    # ------------------------------------------------------------
    # 5. Outros dados
    # ------------------------------------------------------------
    @recent_activities = recent_activities
    @plates_count      = Plate.where(setor: "ROTA").count
    @drivers_count     = Driver.count
    @checklists_today  = Checklist.where(created_at: Date.current.all_day).count
    @stress_tests_count = StressTestImport.count
  end

  # ------------------------------------------------------------
  # 6. Ações e métodos privados (mantidos iguais)
  # ------------------------------------------------------------
  def placas_por_setor
    @setor = "ROTA"
    @placa = params[:placa]

    @placas = Plate.where(setor: "ROTA")
    @placas = @placas.where(placa: @placa) if @placa.present?
    @placas = @placas.order(:placa)

    @dias_rodados = dias_rodados_por_placa(@mes, @ano)

    inicio = Date.new(@ano, @mes, 1)
    @dias_do_mes = (1..inicio.end_of_month.day).to_a

    @setores = Plate.where(setor: "ROTA").group_by(&:setor)

    @status_por_setor = {}
    @setores.each do |setor, placas_do_setor|
      total = placas_do_setor.size
      rodaram = placas_do_setor.count do |plate|
        PlateUtils
          .equivalentes(plate.placa)
          .any? { |placa| @dias_rodados.key?(placa) }
      end
      @status_por_setor[setor] = {
        total: total,
        rodaram: rodaram,
        completo: total == rodaram
      }
    end
  end

  private

  def set_mes_ano
    @mes = params[:mes].presence&.to_i || Date.current.month
    @ano = params[:ano].presence&.to_i || Date.current.year

    @mes = Date.current.month unless (1..12).cover?(@mes)
    @ano = Date.current.year if @ano <= 0
  end

  def dias_rodados_por_placa(mes, ano)
    mapas_do_periodo = Mapa
      .where.not(plate: [nil, ""])
      .pluck(:plate, :data)
      .select do |_, data|
        numeros = data.to_s.gsub(/\D/, "")
        case numeros.length
        when 8
          m = numeros[2,2].to_i
          a = numeros[4,4].to_i
        when 7
          m = numeros[1,2].to_i
          a = numeros[3,4].to_i
        else
          next false
        end
        m == mes && a == ano
      end

    dias_rodados = Hash.new { |h, k| h[k] = [] }
    mapas_do_periodo.each do |placa, data_str|
      dia = extrair_dia(data_str)
      next if dia.nil?
      PlateUtils.equivalentes(placa).each do |placa_equivalente|
        dias_rodados[placa_equivalente] << dia
      end
    end
    dias_rodados.transform_values!(&:uniq)
    dias_rodados
  end

  def vehicles_not_used_in_month(mes, ano, setor = nil)
    dias_rodados = dias_rodados_por_placa(mes, ano)
    plates = setor.present? ? Plate.where(setor: setor) : Plate.all
    all_plates = plates.pluck(:placa)

    not_used = all_plates.reject do |placa|
      PlateUtils.equivalentes(placa).any? { |eq| dias_rodados.key?(eq) }
    end

    Plate.where(placa: not_used)
  end

  def recent_activities
    Mapa.order(created_at: :desc).limit(5).map do |mapa|
      "Mapa #{mapa.plate} em #{mapa.data}"
    end
  rescue
    []
  end

  def extrair_dia(data_str)
    return nil if data_str.blank?
    data = data_str.to_s.gsub(/\D/, "")
    case data.length
    when 8 then data[0,2].to_i
    when 7 then data[0,1].to_i
    when 6 then data[0,1].to_i
    else nil
    end
  end
end
