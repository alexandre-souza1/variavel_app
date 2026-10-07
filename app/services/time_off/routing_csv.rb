require 'csv'

module TimeOff
  class RoutingCsv
    MAX_BYTES = 5.megabytes
    REQUIRED_HEADERS = ['data entrega', 'nro do mapa', 'as / rota', 'placa', 'carga'].freeze
    PLATE_FORMAT = /\A[A-Z]{3}\d[A-Z0-9]\d{2}\z/

    def self.plate(value)
      value.to_s.upcase.gsub(/[\s-]/, '')
    end

    def self.driver_code(value)
      value.to_s.strip.sub(/\A0+(?=\d)/, '')
    end

    def self.verifier
      Rails.application.message_verifier('time_off_routing_csv')
    end

    def self.verify(token, schedule:, date:)
      data = verifier.verified(token, purpose: 'routing_import')
      unless data && data['schedule_id'] == schedule.id && data['date'] == date.iso8601
        raise UpdateDay::InvalidChange, 'A prévia do CSV expirou ou pertence a outra data. Importe o arquivo novamente.'
      end
      data.except('schedule_id')
    end

    def initialize(file:, coverage:)
      @file, @coverage = file, coverage
    end

    def preview
      raise UpdateDay::InvalidChange, 'Selecione um arquivo CSV.' unless @file.respond_to?(:read)
      content = @file.read(MAX_BYTES + 1).to_s
      raise UpdateDay::InvalidChange, 'O CSV deve ter no máximo 5 MB.' if content.bytesize > MAX_BYTES
      utf8 = content.dup.force_encoding('UTF-8')
      content = utf8.valid_encoding? ? utf8 : content.force_encoding('Windows-1252').encode('UTF-8', invalid: :replace, undef: :replace)
      content = content.delete_prefix("\uFEFF")
      csv = CSV.parse(content, headers: true, col_sep: ';', skip_blanks: true, header_converters: ->(header) { normalize(header) })
      unless (REQUIRED_HEADERS - Array(csv.headers)).empty?
        raise UpdateDay::InvalidChange, 'Cabeçalho inválido. Use o CSV de roteirização com Data Entrega, Nro do Mapa, AS / Rota, Placa e Carga.'
      end
      ignored = unrouted = duplicates = 0
      maps = {}
      rows = []
      csv.each_with_index do |row, index|
        next if row.fields.all?(&:blank?)
        if normalize(row['carga']).include?('freteiro')
          ignored += 1
          next
        end
        if csv.headers.include?('roteirizado') && normalize(row['roteirizado']) != 'sim'
          unrouted += 1
          next
        end
        begin
          raw_date = row['data entrega'].to_s.strip
          raise Date::Error unless raw_date.match?(/\A\d{2}\/\d{2}\/\d{4}\z/)
          date = Date.strptime(raw_date, '%d/%m/%Y')
        rescue Date::Error
          raise UpdateDay::InvalidChange, "Linha #{index + 2}: Data Entrega inválida."
        end
        raise UpdateDay::InvalidChange, "O arquivo contém saídas de #{I18n.l(date)}. Abra a cobertura dessa data para importar." unless date == @coverage.date
        plate = self.class.plate(row['placa'])
        map = row['nro do mapa'].to_s.strip
        raise UpdateDay::InvalidChange, "Linha #{index + 2}: placa ou número do mapa inválido." unless plate.match?(PLATE_FORMAT) && map.match?(/\A[1-9]\d*\z/)
        operation = operation_for(row, plate)
        entry = { 'plate' => plate, 'map' => map, 'operation' => operation, 'driver_code' => self.class.driver_code(row['motorista']) }
        if maps[map]
          raise UpdateDay::InvalidChange, "Mapa #{map} aparece com dados diferentes. Corrija o CSV." unless maps[map] == entry
          duplicates += 1
          next
        end
        maps[map] = entry
        rows << entry
      end
      raise UpdateDay::InvalidChange, 'O CSV não contém saídas próprias roteirizadas para importar.' if rows.empty?
      grouped = rows.group_by { |row| row['plate'] }.map do |plate, entries|
        unless entries.map { |e| [e['operation'], e['driver_code']] }.uniq.size == 1
          raise UpdateDay::InvalidChange, "A placa #{plate} tem operações ou motoristas diferentes no arquivo. Revise as saídas antes de importar."
        end
        entries.first.except('map').merge('maps' => entries.map { |e| e['map'] })
      end
      filename = @file.original_filename if @file.respond_to?(:original_filename)
      data = { 'schedule_id' => @coverage.schedule.id, 'date' => @coverage.date.iso8601,
        'filename' => File.basename(filename.to_s.presence || 'roteirizacao.csv')[0, 150],
        'digest' => Digest::SHA256.hexdigest(content), 'ignored_freight' => ignored, 'ignored_unrouted' => unrouted,
        'duplicates' => duplicates, 'rows' => grouped }
      assignments = assign(grouped)
      { metadata: data.except('schedule_id'), token: self.class.verifier.generate(data, purpose: 'routing_import', expires_in: 4.hours), assignments: assignments }
    rescue CSV::MalformedCSVError, EncodingError
      raise UpdateDay::InvalidChange, 'Não foi possível ler o CSV. Verifique o separador ponto e vírgula e a codificação do arquivo.'
    end

    private

    def normalize(value)
      I18n.transliterate(value.to_s.delete_prefix("\uFEFF")).strip.downcase.gsub(/\s+/, ' ')
    end

    def operation_for(row, plate)
      special = @coverage.dimensioning.standard_plate_by_special_route.find { |_, item| self.class.plate(item.plate.placa) == plate }&.first
      return special if special
      operation = normalize(row['as / rota'])
      return 'van' if normalize(row['veiculo']) == 'van' || operation == 'van'
      return 'vespertina' if operation == 'vespertina' || normalize(row['classificacao']) == 'vespertina'
      return 'as' if operation == 'as'
      raise UpdateDay::InvalidChange, "Operação não reconhecida para #{plate}: #{row['as / rota']}." unless operation == 'rota'
      'route'
    end

    def assign(rows)
      cars = Board.new(@coverage).cars
      used = Set.new
      assigned = {}
      rows.each do |row|
        candidates = cars.select { |car| car['operation'] == row['operation'] && !used.include?(car['key']) }
        car = candidates.find { |c| c['plate'] == row['plate'] } || candidates.find do |c|
          member = @coverage.member(c['driver'])
          member && row['driver_code'].present? && self.class.driver_code(member.code_on(@coverage.date)) == row['driver_code']
        end
        next unless car
        used.add(car['key'])
        assigned[row['plate']] = car
      end
      rows.map do |row|
        car = assigned[row['plate']] || cars.find { |candidate| candidate['operation'] == row['operation'] && !used.include?(candidate['key']) }
        raise UpdateDay::InvalidChange, "O CSV excede as posições de #{Coverage::OPERATIONS[row['operation']]} do dimensionamento. Revise a operação ou o dimensionamento." unless car
        used.add(car['key'])
        { 'key' => car['key'], 'plate' => row['plate'] }
      end
    end
  end
end
