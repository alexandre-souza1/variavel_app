require "roo"

class AzMapasImportService
  class Error < StandardError; end

  MONTHS = %w[janeiro fevereiro marco abril maio junho julho agosto setembro outubro novembro dezembro].freeze
  HEADERS = ["ano", "mes", "dia", "% efc", "meta"].freeze
  TMA_HEADERS = ["ano", "nome_mes_abrev", "dia", "tr", "meta"].freeze

  EFD_HEADERS = ["data", "meta (%) - quanto maior melhor", "realizado (%)"].freeze
  SUPRIMENTO_HEADERS = ["data", "meta", "realizado", "atingimento"].freeze

  def initialize(file)
    @files = Array(file).reject(&:blank?)
  end

  def rows
    raise Error, "Selecione um arquivo .xlsx." if @files.empty?

    @without_result = 0
    entries = @files.flat_map { |file| read_rows(file) }
    keys = entries.map { |entry| [entry[:data], entry[:tipo]] }
    raise Error, "Há datas repetidas para o mesmo indicador nas planilhas. Corrija antes de importar." if keys.uniq.size != keys.size

    entries
  end

  def read_rows(file)
    raise Error, "Selecione um arquivo .xlsx." unless File.extname(file.original_filename).downcase == ".xlsx"

    workbook = Roo::Excelx.new(file.path)
    sheet = workbook.sheet(0)
    header_row = (1..[sheet.last_row.to_i, 30].min).find do |number|
      normalized = sheet.row(number).map { |value| normalize(value) }
      [HEADERS, TMA_HEADERS, EFD_HEADERS, SUPRIMENTO_HEADERS].any? { |format| (format - normalized).empty? }
    end
    raise Error, "Cabeçalho esperado: Ano, Mês, Dia, % EFC e Meta; ANO, NOME_MES_ABREV, DIA, TR e Meta; Data, Meta (%) - QUANTO MAIOR MELHOR e Realizado (%); ou Data, Meta, Realizado e Atingimento." unless header_row

    headers = sheet.row(header_row).map { |value| normalize(value) }
    tma = (TMA_HEADERS - headers).empty?
    efd = (EFD_HEADERS - headers).empty?
    suprimento = (SUPRIMENTO_HEADERS - headers).empty?
    columns = if suprimento
                SUPRIMENTO_HEADERS
              else
                efd ? EFD_HEADERS : (tma ? TMA_HEADERS : HEADERS)
              end
    entries = ((header_row + 1)..sheet.last_row).filter_map do |number|
      row = sheet.row(number)
      next if row.all?(&:blank?)

      values = columns.map { |header| row[headers.index(header)] }
      begin
        if suprimento
          raw_date, goal, result, attainment = values
          date = spreadsheet_date(raw_date)
          goal = percentage(goal)
          result = percentage(result)
          attained = attainment.present? ? percentage(attainment) >= 100 : result >= goal
          next({ data: date, tipo: :suprimento, turno: [0], resultado: result, atingiu_meta: attained })
        elsif efd
          raw_date, goal, result = values
          date = spreadsheet_date(raw_date)
          goal = percentage(goal)
          if result.blank?
            @without_result += 1
            next
          end
          result = percentage(result)
          next({ data: date, tipo: :eficiencia_descarga, turno: [1], resultado: result, atingiu_meta: result >= goal })
        end

        year, month, day, result, goal = values
        month_number = MONTHS.index(normalize(month)) || MONTHS.map { |name| name.first(3) }.index(normalize(month))
        date = Date.new(Integer(year.to_s, 10), month_number ? month_number + 1 : Integer(month.to_s, 10), Integer(day.to_s, 10))
        if tma
          result = minutes(result)
          goal = minutes(goal)
          { data: date, tipo: :tempo_atendimento, turno: [0, 1, 2], resultado: result / 60.0, atingiu_meta: result <= goal }
        else
          result = percentage(result)
          goal = percentage(goal)
          { data: date, tipo: :eficiencia_carregamento, turno: [0, 2], resultado: result, atingiu_meta: result >= goal }
        end
      rescue ArgumentError, TypeError
        raise Error, "Linha #{number}: data, #{efd ? "Realizado (%)" : (tma ? "TR" : "% EFC")} ou Meta inválidos. Nenhum lançamento foi importado."
      end
    end
    raise Error, "A planilha não contém resultados diários." if entries.empty? && !efd

    entries
  rescue Error => error
    raise Error, "#{file.original_filename}: #{error.message}"
  rescue StandardError => error
    Rails.logger.warn("Falha na leitura da planilha AZ: #{error.class}")
    raise Error, "Não foi possível ler a planilha. Verifique se é um arquivo Excel .xlsx válido."
  ensure
    workbook&.close
  end

  private :read_rows

  def call
    entries = rows
    imported = skipped = 0
    AzMapa.transaction do
      # Serializa a verificação e a gravação, inclusive com lançamentos manuais.
      AzMapa.connection.execute("LOCK TABLE az_mapas IN SHARE ROW EXCLUSIVE MODE")
      entries.each do |attributes|
        existing = AzMapa.where(data: attributes[:data], tipo: attributes[:tipo])
                         .where("turno && ARRAY[?]::integer[]", attributes[:turno])
        if existing.exists?
          skipped += 1
        else
          AzMapa.create!(attributes)
          imported += 1
        end
      end
    end
    { imported: imported, skipped: skipped, without_result: @without_result }
  rescue ActiveRecord::RecordInvalid => error
    raise Error, "Nenhum lançamento foi importado: #{error.record.errors.full_messages.to_sentence}"
  end

  private

  def normalize(value)
    ActiveSupport::Inflector.transliterate(value.to_s).strip.downcase
  end

  def spreadsheet_date(value)
    return value.to_date if value.is_a?(Date) || value.is_a?(Time)

    text = value.to_s.strip
    format = case text
             when /\A\d{2}\/\d{2}\/\d{4}\z/ then "%d/%m/%Y"
             when /\A\d{4}-\d{2}-\d{2}\z/ then "%Y-%m-%d"
             else raise ArgumentError
             end
    Date.strptime(text, format)
  end

  def minutes(value)
    number = Float(value.to_s.strip.tr(",", "."))
    raise ArgumentError unless number.finite? && number >= 0

    number
  end

  def percentage(value)
    explicit_percent = value.to_s.strip.end_with?("%")
    number = Float(value.to_s.strip.delete_suffix("%").tr(",", "."))
    number *= 100 if !explicit_percent && number <= 1
    raise ArgumentError unless number.finite? && number.between?(0, 100)

    number
  end
end
