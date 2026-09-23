require "roo"

class PeopleCycleImportService
  class ImportError < StandardError; end
  HEADERS = ["colaborador", "etapa ciclo de gente", "resposta"].freeze

  def initialize(file:, cycle:, user:)
    @file, @cycle, @user = file, cycle.to_s.squish.presence || Date.current.year.to_s, user
  end

  def call
    raise ImportError, "Informe um ano válido para o ciclo (ex.: 2026)." unless @cycle.match?(/\A20\d{2}\z/)
    raise ImportError, "Selecione uma planilha .xlsx de até 5 MB." unless @file && File.extname(@file.original_filename).downcase == ".xlsx" && @file.size <= 5.megabytes

    workbook = Roo::Excelx.new(@file.path)
    sheet = workbook.sheet(0)
    headers = sheet.row(1).map { |value| PeopleCycleFeedback.normalize(value) }
    raise ImportError, "Colunas esperadas: Colaborador, ETAPA CICLO DE GENTE e Resposta." unless headers == HEADERS
    raise ImportError, "A planilha deve ter no máximo 5.000 linhas." if sheet.last_row.to_i > 5001

    people = PublicVariableIdentity::PROFILES.flat_map do |profile, model|
      model.where(active: true).pluck(:id, :nome).map { |id, name| [PeopleCycleFeedback.normalize(name), profile, id] }
    end.group_by(&:first)
    rows = []
    seen = {}
    (2..sheet.last_row.to_i).each do |number|
      name, stage, response = sheet.row(number).first(3).map { |value| value.to_s.strip }
      next if [name, stage, response].all?(&:blank?)
      raise ImportError, "Linha #{number}: preencha colaborador, etapa e resposta." if [name, stage, response].any?(&:blank?)
      key = PeopleCycleFeedback.normalize(name)
      stage = stage.squish
      unique = [key, stage]
      raise ImportError, "Linha #{number}: colaborador e etapa repetidos neste arquivo." if seen[unique]
      seen[unique] = true
      matches = people.fetch(key, [])
      match = matches.one? ? matches.first : nil
      rows << { employee_name: name, employee_key: key, stage: stage, response: response,
                profile: match&.[](1), employee_id: match&.[](2) }
    end
    raise ImportError, "A planilha não contém respostas." if rows.empty?

    PeopleCycleFeedback.transaction do
      rows.each do |attributes|
        feedback = PeopleCycleFeedback.find_or_initialize_by(cycle: @cycle, employee_key: attributes[:employee_key], stage: attributes[:stage])
        feedback.update!(attributes.merge(imported_by: @user))
      end
    end
    { count: rows.size, unlinked: rows.count { |row| row[:employee_id].nil? } }
  rescue ImportError
    raise
  rescue StandardError => error
    Rails.logger.warn("Falha na importação do ciclo de gente: #{error.class}")
    raise ImportError, "Não foi possível importar. Confira se o arquivo é uma planilha Excel válida."
  ensure
    workbook&.close
  end
end
