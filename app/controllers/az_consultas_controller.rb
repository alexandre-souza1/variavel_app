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
    @az_mapa = AzMapa.new
  end

  def import
    reference_date = Date.iso8601(params[:points_reference_date]) if params[:points_reference_date].present?
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
      WmsTaskImportJob.enqueue_upload(params[:tasks_file], current_user.id)
      messages << "Tarefas WMS/refugo enviadas para processamento"
    end

    raise ArgumentError, "Selecione pelo menos um arquivo CSV." if messages.empty?

    redirect_to az_consultas_import_path, notice: "Importação iniciada/concluída. #{messages.join(" | ")}."
  rescue ArgumentError => e
    redirect_to az_consultas_import_path, alert: e.message
  rescue StandardError => e
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
    @periodo_mes = params[:periodo_mes].presence || @default_period_date.month
    @periodo_ano = params[:periodo_ano].presence || @default_period_date.year
    @start_date, @end_date = consultation_period(@periodo_ano, @periodo_mes)
    people = Employee.with_career_history.where(matricula: @matricula).limit(2).to_a
    if people.size > 1
      flash.now[:alert] = 'Matrícula ambígua. Solicite ao RH a revisão dos vínculos.'
      return render :new, status: :unprocessable_entity
    end
    person = people.first
    if person
      @report = AzVariableReport.for_period(person: person, from: @start_date, to: @end_date)
      role = @report.role_on(@end_date)
      role = @report.role_on(@report.daily.last[:date]) if !role&.az? && @report.daily.any?
      role = person.employee_roles.az.during(@start_date, @end_date).order(Arel.sql('starts_on DESC NULLS LAST')).first unless role&.az?
    end
    if person && !role&.az?
      flash.now[:alert] = 'Não há vínculo AZ neste período.'
      return render :new, status: :unprocessable_entity
    end
    unless person
      person = if params[:perfil] == 'ajudante'
                 AzAjudante.find_by(matricula: @matricula)
               else
                 Operator.find_by(matricula: @matricula) || AzAjudante.find_by(matricula: @matricula)
               end
    end
    unless person
      flash.now[:alert] = 'Matrícula não encontrada'
      return render :new
    end
    @turno = role ? role.turno : person.turno
    if params[:turno].present? && params[:turno].to_i != @turno
      flash.now[:alert] = "A matrícula #{@matricula} pertence ao turno #{turno_label_for(@turno)} neste período."
      return render :new
    end
    @report ||= AzVariableReport.for_period(person: person, from: @start_date, to: @end_date)
    @closing = person.is_a?(Employee) ? person.variable_closings.where(sector: 'az', year: @periodo_ano, month: @periodo_mes).order(revision: :desc).first : nil
    @report_issues = @report.issues
    @data_inicio, @data_fim = @start_date, @end_date
    @dias_periodo = @period_days = (@end_date - @start_date).to_i + 1
    helper = role ? role.cargo == 'ajudante' : person.is_a?(AzAjudante)
    helper ? prepare_helper_report(person) : prepare_operator_report(person)
    render helper ? :show_ajudante : :show
  rescue Date::Error, EmployeeRole::HistoryError => error
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end

  private

  def prepare_operator_report(person)
    @operator = person
    @valor_tma_operator = @report.rate('valor_tma')
    @valor_efc_operator = @report.rate('valor_efc')
    @valor_wms_operator = @report.rate('tarefa_wms')
    @azmapas = @report.maps.select do |mapa|
      role = @report.role_on(mapa.data)
      role&.az? && role.cargo == 'operador' && mapa.turno.include?(role.turno)
    end
    @total_valor_tma = @report.component(:tma)
    @total_valor_efc = @report.component(:efficiency)
    @total_wms = @report.component(:wms)
    @total_operator_variable = @report.total
    @ondemand_value = @report.component(:ondemand)
    @ondemand_quantity = @report.quantity(:ondemand_quantity)
    @ondemand_daily = @report.operator_daily.filter_map do |day|
      { date: day[:date], quantity: day[:ondemand_quantity], value: day[:ondemand] } if day[:ondemand_quantity].positive?
    end
    @current_page = [params[:page].to_i, 1].max
    @total_pages = [(@report.tasks.size / 15.0).ceil, 1].max
    @current_page = [@current_page, @total_pages].min
    @wms_tasks = @report.tasks.reverse.slice((@current_page - 1) * 15, 15) || []
  end

  def prepare_helper_report(person)
    @helper = person
    @employee_name = person.nome
    @employee_key = EmployeeName.normalize(@employee_name)
    @turno_label = turno_label_for(@turno)
    @points, @refugo_tasks, @ondemand_activities = @report.points, @report.refugo_tasks, @report.activities
    @point_total = @report.quantity(:points)
    @point_value = @report.component(:point_value)
    @reported_point_value = @points.sum(&:reported_value)
    @refugo_count = @report.quantity(:refugo_count)
    @refugo_value = @report.component(:refugo)
    @ondemand_quantity = @report.quantity(:ondemand_quantity)
    @ondemand_value = @report.component(:ondemand)
    @activities_by_type = @ondemand_activities.select { |a| a.rv_category.present? }.group_by(&:activity)
      .map { |activity, records| [activity, records.sum(&:rv_quantity)] }.sort_by { |activity, quantity| [-quantity, activity.to_s] }
    @ondemand_by_category = @ondemand_activities.group_by(&:rv_category).reject { |category, _| category.nil? }
      .sort_by { |category, _| category.to_s }.map { |category, rows| [category, { count: rows.sum(&:rv_quantity), value: rows.sum { |activity| @report.activity_value(activity) } }] }
    @efc_value, @suprimento_value, @remonte_value = %i[efc suprimento remonte].map { |key| @report.component(key) }
    @efc_daily_values, @suprimento_daily_values, @remonte_daily_values = %i[efc suprimento remonte].map do |key|
      @report.helper_daily.select { |day| day[key].positive? }.to_h { |day| [day[:date], day[key]] }
    end
    @daily_summary = @report.helper_daily.select { |day| day[:total_value].positive? || day[:points].nonzero? }.map do |day|
      day.merge(refugo: day[:refugo_count], refugo_value: day[:refugo], ondemand: day[:ondemand_quantity],
        ondemand_value: day[:ondemand], efc_value: day[:efc], suprimento_value: day[:suprimento], remonte_value: day[:remonte])
    end
    @total_activities = @refugo_count + @ondemand_quantity
    @total_variable = @report.total
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

  def turno_label_for(turno)
    { 0 => "A", 1 => "B", 2 => "C" }.fetch(turno, "não informado")
  end

  def authorize_import_management!
    return if current_user&.admin? || current_user&.supervisor?

    redirect_to az_consultas_import_path, alert: "Somente administradores e supervisores podem excluir importações."
  end

  def definir_datas_periodo(azmapas)
    # seleciona apenas a coluna data
    datas = azmapas.pluck(:data)

    @data_inicio = datas.min
    @data_fim = datas.max
    @dias_periodo = (@data_fim - @data_inicio).to_i if @data_inicio && @data_fim
  end
end
