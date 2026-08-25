require "securerandom"

class AzConsultasController < ApplicationController
  before_action :authorize_import_management!, only: :destroy_import

  def index
  end

  def new
    @parametros = ParametroCalculo.all.group_by(&:categoria)
    @default_period_date = period_anchor_date
  end

  def import_form
    @recent_imports = AzRvImport.recent.limit(10)
  end

  def import
    reference_date = Date.iso8601(params[:points_reference_date]) if params[:points_reference_date].present?
    task_file_path = nil
    messages = []

    if params[:points_file].present? || params[:ondemand_file].present?
      result = AzRvCsvImportService.new(
        user: current_user,
        points_file: params[:points_file],
        ondemand_file: params[:ondemand_file],
        points_reference_date: reference_date
      ).call
      messages.concat(result.imports.map { |item| "#{item.source_label}: #{item.rows_imported} linhas" })
    end

    if params[:tasks_file].present?
      task_file_path = stage_shared_tasks_file(params[:tasks_file])
      WmsTaskImportJob.perform_later(task_file_path, current_user.id, params[:tasks_file].original_filename)
      messages << "Tarefas WMS/refugo enviadas para processamento"
    end

    raise ArgumentError, "Selecione pelo menos um arquivo CSV." if messages.empty?

    redirect_to az_consultas_import_path, notice: "Importação iniciada/concluída. #{messages.join(" | ")}."
  rescue ArgumentError => e
    File.delete(task_file_path) if task_file_path.present? && File.exist?(task_file_path)
    redirect_to az_consultas_import_path, alert: e.message
  rescue StandardError => e
    File.delete(task_file_path) if task_file_path.present? && File.exist?(task_file_path)
    Rails.logger.error("Falha na importação de RV do armazém: #{e.class}: #{e.message}")
    redirect_to az_consultas_import_path, alert: "Não foi possível importar os arquivos: #{e.message}"
  end

  def destroy_import
    imported_file = AzRvImport.find(params[:id])
    imported_file.destroy!

    redirect_to az_consultas_import_path, status: :see_other,
                notice: "Importação de #{imported_file.original_filename} excluída com sucesso."
  rescue ActiveRecord::RecordNotFound
    redirect_to az_consultas_import_path, alert: "Importação não encontrada."
  rescue ActiveRecord::RecordNotDestroyed => e
    Rails.logger.error("Falha ao excluir importação de RV: #{e.message}")
    redirect_to az_consultas_import_path, alert: "Não foi possível excluir esta importação."
  end

  def show
    @default_period_date = period_anchor_date

    @matricula = params[:matricula].to_s.strip
    selected_turno = params[:turno].presence&.to_i
    if selected_turno && [0, 1, 2].include?(selected_turno) && turno_mismatch?(@matricula, selected_turno)
      return render :new
    end

    return show_ajudante if params[:perfil] == "ajudante"

    # Os cartões de turno são usados no fluxo antigo de operadores. Se a
    # matrícula existir apenas no cadastro de ajudantes, encaminha para a
    # consulta de RV do ajudante e usa o turno cadastrado automaticamente.
    if params[:matricula].present? && AzAjudante.exists?(matricula: params[:matricula]) && !Operator.exists?(matricula: params[:matricula])
      return show_ajudante
    end

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
        @total_wms = 0
        @total_valor_tma = 0
        @total_valor_efc = 0
        @total_operator_variable = 0

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

        @total_valor_tma = @azmapas.sum do |mapa|
          mapa.tipo == "tempo_atendimento" && mapa.atingiu_meta ? @valor_tma_operator : 0
        end
        @total_valor_efc = @azmapas.sum do |mapa|
          eficiencia_tipo = [0, 2].include?(@turno) ? "eficiencia_carregamento" : "eficiencia_descarga"
          mapa.tipo == eficiencia_tipo && mapa.atingiu_meta ? @valor_efc_operator : 0
        end
        @total_operator_variable = @total_valor_tma + @total_valor_efc + @total_wms

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

  def show_ajudante
    @matricula = params[:matricula].to_s.strip
    @helper = AzAjudante.find_by(matricula: @matricula)

    unless @helper&.nome.present?
      flash.now[:alert] = "Matrícula de ajudante não encontrada."
      return render :new
    end

    @employee_name = @helper.nome.strip
    @employee_key = normalize_employee_key(@employee_name)
    @turno = @helper.turno
    @turno_label = { 0 => "A", 1 => "B", 2 => "C" }.fetch(@turno.to_i, "não informado")

    default_period = period_anchor_date
    @periodo_mes = params[:periodo_mes].presence || default_period.month
    @periodo_ano = params[:periodo_ano].presence || default_period.year
    @start_date, @end_date = consultation_period(@periodo_ano, @periodo_mes)

    @points = AzRvPoint.where(employee_key: @employee_key).between(@start_date, @end_date).order(:reference_date)
    @refugo_tasks = AzRvTask.where(employee_key: @employee_key).between(@start_date, @end_date)
                             .where(task_type: "Blitz Refugo")
                             .order(associated_at: :desc)
    @ondemand_activities = AzRvOnDemandActivity.where(employee_key: @employee_key).between(@start_date, @end_date).order(created_at_source: :desc)

    @point_total = @points.sum(:total_points)
    @point_value = @points.sum(&:montagem_value)
    @reported_point_value = @points.sum(:reported_value)
    @refugo_count = @refugo_tasks.size
    @refugo_value = @refugo_count * BigDecimal("1.10")
    @activities_by_type = @ondemand_activities.where.not(activity: [nil, ""]).reorder(nil).group(:activity).count.sort_by { |activity, count| [-count, activity.to_s] }
    @ondemand_value = @ondemand_activities.sum(&:rv_amount)
    @ondemand_by_category = @ondemand_activities.group_by(&:rv_category).reject { |category, _| category.nil? }.sort_by { |category, _| category.to_s }.map do |category, activities|
      [category, { count: activities.length, value: activities.sum(&:rv_amount) }]
    end
    @daily_summary = build_daily_summary(@points, @refugo_tasks, @ondemand_activities)
    @total_activities = @refugo_count + @ondemand_activities.size
    @total_variable = @point_value + @refugo_value + @ondemand_value
    @period_days = (@end_date - @start_date).to_i + 1

    render :show_ajudante
  end

  def period_anchor_date
    Date.current.day > 18 ? Date.current.next_month : Date.current
  end

  def consultation_period(year, month)
    reference = Date.new(year.to_i, month.to_i, 1)
    [reference.prev_month.change(day: 19), reference.change(day: 18)]
  rescue ArgumentError
    [Date.current.prev_month.change(day: 19), Date.current.change(day: 18)]
  end

  def normalize_employee_key(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
        .downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def turno_mismatch?(matricula, selected_turno)
    operator = Operator.find_by(matricula: matricula)
    person = operator || AzAjudante.find_by(matricula: matricula)
    return false unless person
    return false if person.turno.to_i == selected_turno

    registered_label = turno_label_for(person.turno)
    selected_label = turno_label_for(selected_turno)
    flash.now[:alert] = "A matrícula #{matricula} pertence ao turno #{registered_label}. Selecione o turno #{registered_label} para consultar."
    Rails.logger.info("Consulta AZ bloqueada: matrícula #{matricula} cadastrada no turno #{registered_label}, turno selecionado #{selected_label}.")
    true
  end

  def turno_label_for(turno)
    { 0 => "A", 1 => "B", 2 => "C" }.fetch(turno.to_i, "não informado")
  end

  def build_daily_summary(points, refugo_tasks, ondemand_activities)
    summary = Hash.new do |hash, date|
      hash[date] = {
        points: BigDecimal("0"),
        point_value: BigDecimal("0"),
        refugo: 0,
        refugo_value: BigDecimal("0"),
        ondemand: 0,
        ondemand_value: BigDecimal("0")
      }
    end

    points.each do |point|
      next if point.reference_date.blank?

      daily = summary[point.reference_date]
      daily[:points] += point.total_points.to_d
      daily[:point_value] += point.montagem_value
    end

    refugo_tasks.each do |task|
      date = task.associated_at&.to_date
      next if date.blank?

      daily = summary[date]
      daily[:refugo] += 1
      daily[:refugo_value] += BigDecimal("1.10")
    end

    ondemand_activities.each do |activity|
      date = activity.created_at_source&.to_date
      next if date.blank?

      daily = summary[date]
      daily[:ondemand] += 1
      daily[:ondemand_value] += activity.rv_amount
    end

    summary.sort_by { |date, _| date }.map do |date, daily|
      daily.merge(
        date: date,
        total_value: daily[:point_value] + daily[:refugo_value] + daily[:ondemand_value]
      )
    end
  end

  def authorize_import_management!
    return if current_user&.admin? || current_user&.supervisor?

    redirect_to az_consultas_import_path, alert: "Somente administradores e supervisores podem excluir importações."
  end

  def stage_shared_tasks_file(file)
    path = Rails.root.join("tmp", "shared_tasks_#{Time.current.to_i}_#{SecureRandom.hex(8)}.csv").to_s
    File.binwrite(path, file.read)
    path
  end


  def definir_datas_periodo(azmapas)
    # seleciona apenas a coluna data
    datas = azmapas.pluck(:data)

    @data_inicio = datas.min
    @data_fim = datas.max
    @dias_periodo = (@data_fim - @data_inicio).to_i if @data_inicio && @data_fim
  end
end
