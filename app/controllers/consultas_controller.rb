class ConsultasController < ApplicationController

  def index
  end

  def new
    @parametros = ParametroCalculo.all.group_by(&:categoria)
  end

  def show
    @matricula = params[:matricula]
    @categoria = params[:categoria]&.downcase

    @periodo_mes = params[:periodo_mes]
    employees = Employee.where(matricula: @matricula).where.associated(:employee_roles).distinct.limit(2).to_a
    if employees.size > 1
      @parametros = ParametroCalculo.all.group_by(&:categoria)
      flash.now[:alert] = 'Há mais de um colaborador com essa matrícula. Solicite ao RH a revisão dos vínculos.'
      return render :new, status: :unprocessable_entity
    end
    return show_employee(employees.first) if employees.one?

    if @categoria == "motorista"
      @driver = Driver.find_by(matricula: @matricula)

      if @driver
        normalized_name = @driver.nome.strip.gsub(/\s+/, " ")
        @fuel_consumption = FuelConsumption.where(driver_name: normalized_name).order(:created_at).last

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
        @mapas = Mapa.where(matric_ajudante: @ajudante.promax).or(Mapa.where(matric_ajudante_2: @ajudante.promax))
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
      @driver = nil # Van exige uma vigência cadastrada no RH.

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

    prepare_report_totals! if @mapas && params[:periodo_mes].present?
  end

  private

  def show_employee(employee)
    @employee = employee
    @categoria = 'colaborador'
    @driver = employee
    from = to = nil
    if params[:periodo_mes].present?
      to = Date.new((params[:periodo_ano].presence || Date.current.year).to_i, params[:periodo_mes].to_i, 20)
      from = to.prev_month.change(day: 21)
      @closing = employee.variable_closings.where(year: to.year, month: to.month).order(revision: :desc).first
    end
    if @closing
      snapshot = @closing.result
      @mapas = snapshot.fetch('maps').map { |entry| Mapa.new(entry.fetch('source')) }
      @mapa_calculations = snapshot.fetch('maps').to_h do |entry|
        values = entry.fetch('calculation').deep_symbolize_keys
        %i[valor_cx valor_pdv valor_rec valor_mp].each { |key| values[key] = values[key].to_d }
        [entry.fetch('source').fetch('id'), values]
      end
      @mapa_totals = snapshot.fetch('totals').symbolize_keys.transform_values { |value| value.to_d }
      @career_groups = snapshot.fetch('groups').transform_values { |group| group.symbolize_keys.transform_values { |value| value.to_d } }
      @report_issues = []
    else
      report = EmployeeVariableReport.new(employee, from: from, to: to)
      @mapas = report.maps
      @report_issues = report.issues
      if to
        @mapa_calculations = @mapas.to_h { |mapa| [mapa.id, report.values(mapa)] }
        @mapa_totals = report.totals
        @career_groups = report.groups
      end
    end
    @mapa_totals = @mapa_totals&.merge(caixas_reais: @mapa_totals[:cx_real], pdvs_reais: @mapa_totals[:pdv_real])
    definir_datas_periodo(@mapas)
    render :show
  rescue Date::Error, EmployeeRole::HistoryError => error
    @parametros = ParametroCalculo.all.group_by(&:categoria)
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end

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

  def prepare_report_totals!
    service = MapaRemuneracaoService.new(@categoria)
    @mapa_calculations = {}

    @mapas.each do |mapa|
      @mapa_calculations[mapa.id] = service.values(mapa)
    end

    totals = service.totals(@mapas)
    @mapa_totals = totals.merge(
      caixas_reais: totals[:cx_real],
      pdvs_reais: totals[:pdv_real]
    )
  end

  def mapa_values(mapa)
    values = MapaRemuneracaoService.new(@categoria).values(mapa)
    [values[:valor_cx], values[:valor_pdv], values[:valor_rec]]
  end
end
