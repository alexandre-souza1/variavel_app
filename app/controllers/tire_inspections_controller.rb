require "csv"

class TireInspectionsController < ApplicationController
  SORT_OPTIONS = [["Aferições mais recentes", "newest"], ["Aferições mais antigas", "oldest"], ["Menor sulco primeiro (mm)", "depth_asc"], ["Maior sulco primeiro (mm)", "depth_desc"], ["Maior divergência primeiro", "increase_desc"]].freeze
  PAGE_SIZES = [25, 50, 100, 200].freeze
  before_action :authenticate_user!

  def index
    @per_page = PAGE_SIZES.include?(params[:per_page].to_i) ? params[:per_page].to_i : 50
    @sort = SORT_OPTIONS.any? { |_, key| key == params[:sort] } ? params[:sort] : "newest"
    @pressure_view = params[:view] == "pressure"
    @start_date = params[:start_date].present? ? Date.iso8601(params[:start_date]) : Date.current << 3
    @end_date = params[:end_date].present? ? Date.iso8601(params[:end_date]) : Date.current
    if @end_date < @start_date || @end_date > Date.current || @end_date > (@start_date >> 12)
      raise ArgumentError
    end
    @baseline_date = @start_date << 3
    @query = params[:q].to_s.strip
    @status = params[:status].to_s
    inspections = Prolog::InspectionsClient.new.fetch(start_time: @baseline_date.in_time_zone, end_time: (@end_date + 1).in_time_zone)
    if @pressure_view
      prepare_pressure(inspections)
    else
      @report = Prolog::InspectionDivergences.new(inspections, start_time: @start_date.in_time_zone, end_time: @end_date.in_time_zone.end_of_day)
      @rows = @report.rows.select do |row|
        searchable = [row[:serial], row[:previous][:record].dig("vehicle", "licensePlate"), row[:current][:record].dig("vehicle", "licensePlate")].join(" ").downcase
        searchable.include?(@query.downcase)
      end
      @severity_counts = @rows.group_by { |row| row[:severity] }.transform_values(&:size)
      @rows = @rows.select { |row| row[:severity] == @status } if Prolog::InspectionDivergences::SEVERITIES.key?(@status)
    end
    sort_divergences unless @pressure_view
    respond_to do |format|
      format.html do
        prepare_charts
        @total_rows = @rows.size
        @total_pages = [(@total_rows / @per_page.to_f).ceil, 1].max
        @page = [[params[:page].to_i, 1].max, @total_pages].min
        @rows = @rows.slice((@page - 1) * @per_page, @per_page) || []
      end
      format.csv { send_data (@pressure_view ? pressure_csv : export_csv), filename: "#{@pressure_view ? 'calibragem' : 'divergencias'}-pneus-#{@start_date}-#{@end_date}.csv", type: "text/csv; charset=utf-8" }
    end
  rescue ArgumentError
    @error = "Informe um período válido de até 12 meses, sem datas futuras."
    render :index, formats: [:html], status: :unprocessable_entity
  rescue Prolog::InspectionsClient::Error => e
    @error = e.message
    render :index, formats: [:html], status: :service_unavailable
  end

  private

  def sort_divergences
    @rows.sort_by! do |row|
      value = case @sort
      when "depth_asc" then row[:current][:depth]
      when "depth_desc" then -row[:current][:depth]
      when "newest" then -row[:current][:time].to_f
      when "oldest" then row[:current][:time].to_f
      else -row[:delta]
      end
      [value, -row[:current][:time].to_f, row[:tire_id].to_s, row[:groove], row[:current][:record]["id"].to_s]
    end
  end

  def prepare_charts
    @affected_inspections = @rows.map { |row| row[:current][:record].values_at("source", "id") }.uniq.size
    @affected_tires = @rows.map { |row| row[:tire_id] }.uniq.size
    @chart_distribution = @rows.group_by do |row|
      @pressure_view ? helpers.pressure_status_label(row[:status]) : Prolog::InspectionDivergences::SEVERITIES.fetch(row[:severity])
    end.transform_values(&:size)
    by_month = @rows.group_by { |row| row[:current][:time].in_time_zone.to_date.beginning_of_month }
    month = @start_date.beginning_of_month
    @chart_evolution = {}
    while month <= @end_date
      @chart_evolution[month.strftime("%m/%Y")] = Array(by_month[month]).map { |row| row[:current][:record].values_at("source", "id") }.uniq.size
      month = month.next_month
    end
  end

  def prepare_pressure(inspections)
    @report = Prolog::PressureHistory.new(inspections, start_time: @start_date.in_time_zone, end_time: @end_date.in_time_zone.end_of_day)
    @rows = @report.rows.select do |row|
      [row[:serial], row[:current][:record].dig("vehicle", "licensePlate"), row[:following]&.dig(:record, "vehicle", "licensePlate")].join(" ").downcase.include?(@query.downcase)
    end
    @pressure_counts = @rows.group_by { |r| r[:status] }.transform_values(&:size)
    @rows = @rows.select { |r| r[:status] == @status } if %w[persisted normalized pending current_low awaiting_month unknown].include?(@status)
  end

  def pressure_csv
    "\uFEFF" + CSV.generate(col_sep: ";") do |csv|
      csv << ["Pneu", "Vida", "Data", "Placa", "Responsável", "Aferição", "Pressão", "Recomendada", "Déficit", "Leituras baixas consecutivas", "Situação", "Data seguinte", "Pressão seguinte", "Recomendada seguinte", "Aferição seguinte", "Responsável seguinte", "Limite (PSI)", "Limite seguinte (PSI)"]
      @rows.each do |row|
        current = row[:current]
        following = row[:following]
        values = [row[:serial], row[:life], current[:time].in_time_zone.to_s, current[:record].dig("vehicle", "licensePlate"), current[:record].dig("submittedBy", "name"), current[:record]["id"], current[:pressure].to_s("F"), current[:recommended].to_s("F"), row[:deficit].to_s("F"), row[:streak], helpers.pressure_status_label(row[:status]), following&.dig(:time)&.in_time_zone&.to_s, following&.dig(:pressure)&.to_s("F"), following&.dig(:recommended)&.to_s("F"), following&.dig(:record, "id"), following&.dig(:record, "submittedBy", "name"), current[:minimum].round(2).to_s("F"), following&.dig(:minimum)&.round(2)&.to_s("F")]
        csv << values.map { |value| value.is_a?(String) && value.match?(/\A[=+\-@\t\r\n]/) ? "'#{value}" : value }
      end
    end
  end

  def export_csv
    "\uFEFF" + CSV.generate(col_sep: ";") do |csv|
      csv << ["Pneu", "Vida", "Sulco", "Aferição anterior", "Data anterior", "Placa anterior", "Responsável anterior", "Medida anterior (mm)", "Aferição seguinte", "Data seguinte", "Placa seguinte", "Responsável seguinte", "Medida seguinte (mm)", "Aumento (mm)", "Classificação"]
      @rows.each do |row|
        values = [row[:serial], row[:life], row[:groove]]
        [:previous, :current].each do |side|
          reading = row[side]
          values.concat([reading[:record]["id"], reading[:time].in_time_zone.strftime("%d/%m/%Y %H:%M"), reading[:record].dig("vehicle", "licensePlate"), reading[:record].dig("submittedBy", "name"), reading[:depth].to_s("F").tr(".", ",")])
        end
        values.concat([row[:delta].to_s("F").tr(".", ","), Prolog::InspectionDivergences::SEVERITIES.fetch(row[:severity])])
        csv << values.map { |value| value.is_a?(String) && value.match?(/\A[=+\-@\t\r\n]/) ? "'#{value}" : value }
      end
    end
  end
end
