class DashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_mes_ano, only: [:index, :placas_por_setor, :mapas]

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

  def mapas
    @periodo_tipo = params[:periodo_tipo].presence || "mes"
    @periodo_inicio, @periodo_fim = periodo_dashboard_mapas(@periodo_tipo, @mes, @ano)

    @mapas = mapas_no_periodo(@periodo_inicio, @periodo_fim)
    @total_mapas = @mapas.size
    @total_cx_real = @mapas.sum { |mapa| mapa.recarga == "SIM" ? 0 : mapa.cx_real.to_f }
    @total_pdv_real = @mapas.sum { |mapa| mapa.recarga == "SIM" ? 0 : mapa.pdv_real.to_f }
    @total_recargas = @mapas.count { |mapa| mapa.recarga == "SIM" }
    @ranking_ajudantes = ranking_ajudantes(@mapas)
    @ranking_motoristas = ranking_motoristas(@mapas)
    @ranking_placas = ranking_placas(@mapas)
    @total_remuneracao_motoristas = @ranking_motoristas.sum { |item| item[:valor_total] }
    @total_remuneracao_ajudantes = @ranking_ajudantes.sum { |item| item[:valor_total] }
    # Dados para gráficos
    @motoristas_top10_mapas = @ranking_motoristas.first(10).map { |m| [m[:nome], m[:mapas]] }
    @motoristas_top10_valor = @ranking_motoristas.first(10).map { |m| [m[:nome], m[:valor_total]] }
    @ajudantes_top10_valor = @ranking_ajudantes.first(10).map { |m| [m[:nome], m[:valor_total]] }
    @placas_top10_mapas = @ranking_placas.first(10).map { |p| [p[:placa], p[:mapas]] }

    @mapas_por_dia = @mapas
      .group_by { |m| m.data_formatada }
      .transform_values(&:count)
      .sort.to_h
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

  def periodo_dashboard_mapas(tipo, mes, ano)
    fim_periodo = Date.new(ano, mes, 20)
    inicio_periodo = fim_periodo.prev_month.change(day: 21)

    case tipo
    when "primeira_quinzena"
      [inicio_periodo, inicio_periodo + 14.days]
    when "segunda_quinzena"
      [inicio_periodo + 15.days, fim_periodo]
    else
      [inicio_periodo, fim_periodo]
    end
  end

  def mapas_no_periodo(inicio, fim)
    anos = (inicio.year..fim.year).to_a
    scope = Mapa.where.not(data: [nil, ""])
    scope = scope.where(anos.map { "data LIKE ?" }.join(" OR "), *anos.map { |ano| "%#{ano}" })

    scope.select do |mapa|
      data = mapa.data_formatada
      data.present? && data >= inicio && data <= fim
    end
  end

  def ranking_motoristas(mapas)
    promaxes = mapas.map { |mapa| mapa.matric_motorista.to_s }.reject(&:blank?).uniq
    drivers_by_promax = Driver.where(promax: promaxes).index_by { |driver| driver.promax.to_s }

    mapas
      .group_by(&:matric_motorista)
      .map do |promax, mapas_motorista|
        driver = drivers_by_promax[promax.to_s]
        next unless driver  # <-- ignora motoristas sem registro na tabela drivers

        totais = totais_remuneracao_motorista(mapas_motorista)

        {
          promax: promax,
          nome: driver.nome,  # agora garantido que existe
          matricula: driver.matricula,
          mapas: mapas_motorista.size,
          placas: mapas_motorista.map(&:plate).compact_blank.uniq.size,
          cx_real: totais[:cx_real],
          pdv_real: totais[:pdv_real],
          recargas: totais[:recargas],
          devolucoes: totais[:devolucoes],
          percentual_devolucao: totais[:percentual_devolucao],
          bonus_devolucao: totais[:bonus_devolucao],
          valor_total: totais[:valor_total]
        }
      end
      .compact  # remove os nils gerados pelo 'next unless driver'
      .sort_by { |item| [-item[:mapas], -item[:valor_total], item[:nome].to_s] }
  end

  def ranking_ajudantes(mapas)
    promaxes = mapas.map { |mapa| mapa.matric_ajudante.to_s }.reject(&:blank?).uniq
    ajudantes_by_promax = Ajudante.where(promax: promaxes).index_by { |a| a.promax.to_s }

    mapas
      .group_by(&:matric_ajudante)
      .map do |promax, mapas_ajudante|
        ajudante = ajudantes_by_promax[promax.to_s]
        next unless ajudante

        totais = totais_remuneracao_ajudante(mapas_ajudante)  # novo método

        {
          promax: promax,
          nome: ajudante.nome,
          matricula: ajudante.matricula,
          mapas: mapas_ajudante.size,
          placas: mapas_ajudante.map(&:plate).compact_blank.uniq.size,
          cx_real: totais[:cx_real],
          pdv_real: totais[:pdv_real],
          recargas: totais[:recargas],
          devolucoes: totais[:devolucoes],
          percentual_devolucao: totais[:percentual_devolucao],
          bonus_devolucao: totais[:bonus_devolucao],
          valor_total: totais[:valor_total]
        }
      end
      .compact
      .sort_by { |item| [-item[:mapas], -item[:valor_total], item[:nome].to_s] }
  end

  # Novo método de cálculo (igual ao de motorista, mas usando parâmetros de ajudante)
  def totais_remuneracao_ajudante(mapas)
    valor_caixa = ParametroCalculo.valor_para(categoria: "ajudante", nome: "valor_caixa").to_f
    valor_entrega = ParametroCalculo.valor_para(categoria: "ajudante", nome: "valor_entrega").to_f
    valor_recarga = ParametroCalculo.valor_para(categoria: "ajudante", nome: "valor_recarga").to_f
    valor_bonus_devolucao = ParametroCalculo.valor_para(categoria: "geral", nome: "bonus_devolucao").to_f

    total_valor = 0
    total_cx_real = 0
    total_pdv_real = mapas.sum { |mapa| mapa.recarga == "SIM" ? 0 : mapa.pdv_real.to_f }
    total_pdv_total = mapas.sum { |mapa| mapa.recarga == "SIM" ? 0 : mapa.pdv_total.to_f }
    total_recargas = 0

    mapas.each do |mapa|
      if mapa.fator == 2
        valor_cx = mapa.cx_real.to_f * valor_caixa / 2
        valor_pdv = mapa.pdv_real.to_f * valor_entrega / 2
      else
        multiplicador = mapa.fator == 0 && mapa.pdv_total.to_f >= 2 ? 2 : 1
        valor_cx = mapa.cx_real.to_f * valor_caixa * multiplicador
        valor_pdv = mapa.pdv_real.to_f * valor_entrega * multiplicador
      end

      valor_rec = mapa.recarga == "SIM" ? valor_recarga : 0
      valor_mapa = mapa.recarga == "SIM" ? valor_rec : valor_cx + valor_pdv

      total_cx_real += mapa.cx_real.to_f unless mapa.recarga == "SIM"
      total_recargas += 1 if mapa.recarga == "SIM"
      total_valor += valor_mapa
    end

    devolucoes = total_pdv_total - total_pdv_real
    percentual_devolucao = total_pdv_total.zero? ? 0 : devolucoes / total_pdv_total
    bonus_devolucao = mapas.size >= 15 && percentual_devolucao <= 0.03 ? valor_bonus_devolucao : 0

    {
      cx_real: total_cx_real,
      pdv_real: total_pdv_real,
      recargas: total_recargas,
      devolucoes: devolucoes,
      percentual_devolucao: percentual_devolucao,
      bonus_devolucao: bonus_devolucao,
      valor_total: total_valor + bonus_devolucao
    }
  end

  def ranking_placas(mapas)
    mapas
      .group_by { |mapa| mapa.plate.presence || "Sem placa" }
      .map do |placa, mapas_placa|
        {
          placa: placa,
          mapas: mapas_placa.size,
          motoristas: mapas_placa.map(&:matric_motorista).compact_blank.uniq.size,
          cx_real: mapas_placa.sum { |mapa| mapa.recarga == "SIM" ? 0 : mapa.cx_real.to_f },
          pdv_real: mapas_placa.sum { |mapa| mapa.recarga == "SIM" ? 0 : mapa.pdv_real.to_f },
          recargas: mapas_placa.count { |mapa| mapa.recarga == "SIM" }
        }
      end
      .sort_by { |item| [-item[:mapas], item[:placa].to_s] }
  end

  def totais_remuneracao_motorista(mapas)
    valor_caixa = ParametroCalculo.valor_para(categoria: "motorista", nome: "valor_caixa").to_f
    valor_entrega = ParametroCalculo.valor_para(categoria: "motorista", nome: "valor_entrega").to_f
    valor_recarga = ParametroCalculo.valor_para(categoria: "motorista", nome: "valor_recarga").to_f
    valor_bonus_devolucao = ParametroCalculo.valor_para(categoria: "geral", nome: "bonus_devolucao").to_f

    total_valor = 0
    total_cx_real = 0
    total_pdv_real = mapas.sum { |mapa| mapa.recarga == "SIM" ? 0 : mapa.pdv_real.to_f }
    total_pdv_total = mapas.sum { |mapa| mapa.recarga == "SIM" ? 0 : mapa.pdv_total.to_f }
    total_recargas = 0

    mapas.each do |mapa|
      if mapa.fator == 2
        valor_cx = mapa.cx_real.to_f * valor_caixa / 2
        valor_pdv = mapa.pdv_real.to_f * valor_entrega / 2
      else
        multiplicador = mapa.fator == 0 && mapa.pdv_total.to_f >= 2 ? 2 : 1
        valor_cx = mapa.cx_real.to_f * valor_caixa * multiplicador
        valor_pdv = mapa.pdv_real.to_f * valor_entrega * multiplicador
      end

      valor_rec = mapa.recarga == "SIM" ? valor_recarga : 0
      valor_mapa = mapa.recarga == "SIM" ? valor_rec : valor_cx + valor_pdv

      total_cx_real += mapa.cx_real.to_f unless mapa.recarga == "SIM"
      total_recargas += 1 if mapa.recarga == "SIM"
      total_valor += valor_mapa
    end

    devolucoes = total_pdv_total - total_pdv_real
    percentual_devolucao = total_pdv_total.zero? ? 0 : devolucoes / total_pdv_total
    bonus_devolucao = mapas.size >= 15 && percentual_devolucao <= 0.03 ? valor_bonus_devolucao : 0

    {
      cx_real: total_cx_real,
      pdv_real: total_pdv_real,
      recargas: total_recargas,
      devolucoes: devolucoes,
      percentual_devolucao: percentual_devolucao,
      bonus_devolucao: bonus_devolucao,
      valor_total: total_valor + bonus_devolucao
    }
  end
end
