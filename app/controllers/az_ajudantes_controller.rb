require "csv"

class AzAjudantesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_az_ajudante, only: %i[show edit update destroy]
  before_action :only_admin, only: :destroy_all
  before_action :admin_or_supervisor, only: %i[new create edit update destroy import_csv]
  before_action :everyone_can_access, only: %i[index show import]
  include AzAjudantesHelper

  def index
    scope = params[:status] == "inactive" ? AzAjudante.inactive : AzAjudante.active
    @az_ajudantes = scope.order(:nome)
  end

  def import
  end

  def import_csv
    file = params[:file]

    if file.blank?
      redirect_to import_az_ajudantes_path, alert: "Selecione um arquivo CSV para importar."
      return
    end

    imported = 0

    begin
      CSV.parse(csv_content(file), headers: true, col_sep: ";", liberal_parsing: true).each do |row|
        matricula = csv_value(row, "matricula", "matrícula")
        next if matricula.blank?

        ajudante = AzAjudante.find_or_initialize_by(matricula: matricula.to_i)
        ajudante.assign_attributes(
          nome: csv_value(row, "nome"),
          cpf: csv_value(row, "cpf"),
          data_nascimento: parse_date(csv_value(row, "data_nascimento", "data nascimento")),
          turno: parse_turno(csv_value(row, "turno"))
        )
        ajudante.save!
        imported += 1
      end

      redirect_to az_ajudantes_path, notice: "#{imported} ajudantes importados com sucesso."
    rescue StandardError => e
      redirect_to import_az_ajudantes_path, alert: "Erro ao importar: #{e.message}"
    end
  end

  def show
  end

  def new
    @az_ajudante = AzAjudante.new
  end

  def edit
  end

  def create
    @az_ajudante = AzAjudante.new(az_ajudante_params)

    respond_to do |format|
      if @az_ajudante.save
        format.html { redirect_to @az_ajudante, notice: "Ajudante do Armazém cadastrado com sucesso." }
        format.json { render :show, status: :created, location: @az_ajudante }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @az_ajudante.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @az_ajudante.update(az_ajudante_params)
        format.html { redirect_to @az_ajudante, notice: "Ajudante do Armazém atualizado com sucesso." }
        format.json { render :show, status: :ok, location: @az_ajudante }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @az_ajudante.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    respond_to do |format|
      if @az_ajudante.retire!
        format.html { redirect_to az_ajudantes_path, status: :see_other, notice: "Ajudante inativado com sucesso. O histórico foi preservado." }
        format.json { head :no_content }
      else
        format.html { redirect_to @az_ajudante, alert: "Não foi possível remover o ajudante." }
        format.json { render json: @az_ajudante.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy_all
    count = AzAjudante.update_all(active: false, retired_at: Date.current, updated_at: Time.current)
    redirect_to az_ajudantes_path, notice: "#{count} ajudantes foram inativados."
  end

  private

  def set_az_ajudante
    @az_ajudante = AzAjudante.find(params[:id])
  end

  def az_ajudante_params
    params.require(:az_ajudante).permit(:matricula, :nome, :cpf, :data_nascimento, :turno)
  end

  def only_admin
    redirect_back fallback_location: root_path, alert: "Acesso negado" unless current_user.admin?
  end

  def admin_or_supervisor
    return if current_user.admin? || current_user.supervisor?

    redirect_back fallback_location: root_path, alert: "Acesso negado"
  end

  def everyone_can_access
    return if current_user.admin? || current_user.supervisor? || current_user.user?

    redirect_back fallback_location: root_path, alert: "Acesso negado"
  end

  def csv_value(row, *headers)
    normalized_headers = headers.map { |header| normalize_header(header) }
    source_header = row.headers.find { |header| normalized_headers.include?(normalize_header(header)) }
    row[source_header].to_s.strip.presence
  end

  def csv_content(file)
    raw_content = File.binread(file.path)
    raw_content = raw_content.byteslice(3..-1) if raw_content.start_with?("\xEF\xBB\xBF".b)

    raw_content.dup.force_encoding(Encoding::UTF_8).encode(Encoding::UTF_8)
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    raw_content.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
  end

  def normalize_header(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
        .downcase.gsub(/[^a-z0-9]+/, "_").sub(/\A_/, "").sub(/_\z/, "")
  end

  def parse_turno(value)
    normalized = value.to_s.strip.upcase
    return turno_map[normalized] if turno_map.key?(normalized)

    number = Integer(normalized, exception: false)
    return number if number && (0..2).cover?(number)

    nil
  end

  def parse_date(value)
    return if value.blank?

    Date.strptime(value, "%d/%m/%Y")
  rescue ArgumentError
    begin
      Date.parse(value)
    rescue ArgumentError, Date::Error
      nil
    end
  end
end
