class DashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_mes_ano, only: [:index, :placas_por_setor]

  def index
    # Tarefas pendentes
    @pending_tasks = Task.includes(bucket: :action_plan)
                         .where(completed: [false, nil])

    # Tarefas com vencimento próximo (hoje + 2 dias)
    @tasks_due_soon = Task.where(completed: [false, nil])
                          .where("due_at <= ?", 2.days.from_now.end_of_day)
                          .order(due_at: :asc)
                          .limit(5)

    # Custos do mês atual
    @current_month_cost = Invoice
      .where(date: Date.current.beginning_of_month..Date.current.end_of_month)
      .sum(:total)

    # Total de faturas no mês
    @total_invoices = Invoice
      .where(date: Date.current.beginning_of_month..Date.current.end_of_month)
      .count

    # ---------- Gastos por categoria (gráfico donut) ----------
    @expenses_by_category = Invoice
      .where(date: Date.current.beginning_of_month..Date.current.end_of_month)
      .joins(:budget_category)
      .group('budget_categories.name')
      .sum(:total)

    # ---------- Métricas apenas para frotas ROTA ----------
    @total_vehicles = Plate.where(setor: "ROTA").count

    # Veículos por tipo (apenas ROTA)
    @vehicles_by_type = Plate.where(setor: "ROTA").group(:tipo).count

    # Veículos que NÃO rodaram no mês (apenas ROTA)
    @vehicles_not_used_this_month = vehicles_not_used_in_month(@mes, @ano, "ROTA")

    # Dados para gráfico de custos mensais (últimos 12 meses)
    @monthly_costs = monthly_costs_chart_data

    # (Opcional) Últimas atividades
    @recent_activities = recent_activities

    # ---------- Último mapa enviado (baseado no campo 'data') ----------
    @last_map = Mapa.where.not(data: [nil, ""])
                    .order(created_at: :desc)
                    .first

    if @last_map.present?
      data_str = @last_map.data.to_s.gsub(/\D/, "")
      begin
        case data_str.length
        when 8
          day = data_str[0,2].to_i
          month = data_str[2,2].to_i
          year = data_str[4,4].to_i
          @last_map_date = Date.new(year, month, day) rescue nil
        when 7
          day = data_str[0,1].to_i
          month = data_str[1,2].to_i
          year = data_str[3,4].to_i
          @last_map_date = Date.new(year, month, day) rescue nil
        else
          @last_map_date = nil
        end
      rescue
        @last_map_date = nil
      end
    else
      @last_map_date = nil
    end

    # Outros dados que você já tinha
    @plates_count = Plate.where(setor: "ROTA").count
    @drivers_count = Driver.count
    @checklists_today = Checklist.where(created_at: Date.current.all_day).count
    @stress_tests_count = StressTestImport.count
  end

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
    @mes = params[:mes].to_i.presence || Date.current.month
    @ano = params[:ano].to_i.presence || Date.current.year
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

  def monthly_costs_chart_data
    invoices_by_month = Invoice
      .where(date: 11.months.ago.beginning_of_month..Date.current.end_of_month)
      .group("DATE_TRUNC('month', date)")
      .sum(:total)

    invoices_by_month.map do |month, total|
      { month: month.strftime("%b %Y"), cost: total.to_f }
    end
  rescue
    []
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
