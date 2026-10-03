require 'csv'

module Pcd
  class RoutingCsv
    MAX_BYTES = 5.megabytes
    HEADERS = ['data entrega', 'nro do mapa', 'as / rota', 'placa', 'carga', 'cidades +entregas', 'regiao +entregas'].freeze

    def self.verifier = Rails.application.message_verifier('pcd_routing_csv')

    def self.verify(token, date:)
      source = verifier.verified(token, purpose: 'pcd_import')
      raise TimeOff::UpdateDay::InvalidChange, 'A prévia expirou ou pertence a outra data. Importe novamente.' unless source && source['date'] == date.iso8601
      source
    end

    def initialize(file:, board:)
      @file, @board = file, board
    end

    def preview
      raise TimeOff::UpdateDay::InvalidChange, 'Selecione um CSV de roteirização.' unless @file.respond_to?(:read)
      content = @file.read(MAX_BYTES + 1).to_s
      raise TimeOff::UpdateDay::InvalidChange, 'O CSV deve ter no máximo 5 MB.' if content.bytesize > MAX_BYTES
      utf8 = content.dup.force_encoding('UTF-8')
      content = utf8.valid_encoding? ? utf8 : content.force_encoding('Windows-1252').encode('UTF-8', invalid: :replace, undef: :replace)
      content = content.delete_prefix("\uFEFF")
      table = CSV.parse(content, col_sep: ';', headers: true, skip_blanks: true, header_converters: ->(v) { normalize(v) })
      raise TimeOff::UpdateDay::InvalidChange, 'Use o relatório PW00943S com Data Entrega, Mapa, Placa, Carga, Cidades +Entregas e Região +Entregas.' unless (HEADERS - Array(table.headers)).empty?
      maps = {}
      ignored = duplicates = 0
      table.each_with_index do |row, i|
        next if row.fields.all?(&:blank?)
        if table.headers.include?('roteirizado') && normalize(row['roteirizado']) != 'sim'
          ignored += 1
          next
        end
        raw_date = row['data entrega'].to_s.strip
        begin
          raise Date::Error unless raw_date.match?(/\A\d{2}\/\d{2}\/\d{4}\z/)
          date = Date.strptime(raw_date, '%d/%m/%Y')
        rescue Date::Error
          raise TimeOff::UpdateDay::InvalidChange, "Linha #{i + 2}: Data Entrega inválida."
        end
        raise TimeOff::UpdateDay::InvalidChange, "O CSV é de #{I18n.l(date)}. Abra o PCD dessa data." unless date == @board.date
        plate = TimeOff::RoutingCsv.plate(row['placa'])
        number = row['nro do mapa'].to_s.strip
        raise TimeOff::UpdateDay::InvalidChange, "Linha #{i + 2}: placa ou mapa inválido." unless plate.match?(TimeOff::RoutingCsv::PLATE_FORMAT) && number.match?(/\A[1-9]\d*\z/)
        freight = normalize(row['carga']).include?('freteiro')
        code = TimeOff::RoutingCsv.driver_code(row['motorista'])
        operation = operation_for(row, plate, code, freight)
        entry = { 'number' => number, 'plate' => plate, 'driver_code' => code, 'freight' => freight, 'operation' => operation,
          'cities' => row['cidades +entregas'].to_s.strip, 'region' => row['regiao +entregas'].to_s.strip,
          'deliveries' => row['entregas'].to_s, 'km' => row['km prev.'].to_s, 'duration' => row['tempo prev. (+almoco)'].to_s,
          'boxes' => row['total de caixas'].to_s, 'box_occupancy' => row['% ocupacao caixas'].to_s,
          'weight' => row['total peso'].to_s, 'weight_occupancy' => row['% ocupacao peso'].to_s,
          'vehicle' => row['veiculo'].to_s, 'classification' => row['classificacao'].to_s }
        if maps[number]
          raise TimeOff::UpdateDay::InvalidChange, "Mapa #{number} tem dados conflitantes no arquivo." unless maps[number] == entry
          duplicates += 1
        else
          maps[number] = entry
        end
      end
      raise TimeOff::UpdateDay::InvalidChange, 'Não há rotas roteirizadas no CSV.' if maps.empty?
      groups = maps.values.group_by { |map| map['plate'] }.map do |plate, entries|
        raise TimeOff::UpdateDay::InvalidChange, "A placa #{plate} tem motoristas ou operações conflitantes; revise o arquivo." unless entries.map { |e| e.values_at('driver_code', 'operation', 'freight') }.uniq.size == 1
        { 'plate' => plate, 'operation' => entries.first['operation'], 'freight' => entries.first['freight'],
          'driver_code' => entries.first['driver_code'], 'maps' => entries }
      end
      filename = @file.original_filename if @file.respond_to?(:original_filename)
      source = { 'date' => @board.date.iso8601, 'filename' => File.basename(filename.to_s.presence || 'roteirizacao.csv')[0, 150],
        'digest' => Digest::SHA256.hexdigest(content), 'ignored_unrouted' => ignored, 'duplicates' => duplicates, 'rows' => groups }
      { source: source, token: self.class.verifier.generate(source, purpose: 'pcd_import', expires_in: 4.hours), cars: self.class.merge(@board, source) }
    rescue CSV::MalformedCSVError, EncodingError
      raise TimeOff::UpdateDay::InvalidChange, 'Não foi possível ler o CSV. Confira o separador ponto e vírgula e a codificação.'
    end

    def self.merge(board, source)
      existing = board.cars.deep_dup
      used = Set.new
      matched = {}
      source['rows'].each do |row|
        candidate = existing.find { |car| !used.include?(car['key']) && (Array(car['maps']).map { |m| m['number'] } & row['maps'].map { |m| m['number'] }).any? }
        candidate ||= existing.find { |car| !used.include?(car['key']) && car['plate'] == row['plate'] }
        candidate ||= existing.find do |car|
          person = board.member(car['driver'])
          !used.include?(car['key']) && !row['freight'] && car['operation'] == row['operation'] && person && row['driver_code'].present? && TimeOff::RoutingCsv.driver_code(person['code']) == row['driver_code']
        end
        if candidate
          matched[row['plate']] = candidate
          used.add(candidate['key'])
        end
      end
      imported = source['rows'].map do |row|
        car = matched[row['plate']] || existing.find { |c| !used.include?(c['key']) && !row['freight'] && c['operation'] == row['operation'] && Array(c['maps']).empty? }
        fresh = car.nil? || Array(car['maps']).empty?
        car ||= board.defaults('key' => "map:#{row['maps'].first['number']}", 'operation' => row['operation'], 'position' => 0,
          'helper_count' => row['freight'] || %w[as van].include?(row['operation']) ? 0 : 1, 'freight' => row['freight'])
        used.add(car['key'])
        # Preserve a supervisor's replacement plate when refreshing the same maps.
        car['plate'] = row['plate'] if fresh || car['plate'] == car['imported_plate']
        car.merge!('maps' => row['maps'], 'imported_plate' => row['plate'], 'freight' => row['freight'], 'scheduled' => fresh ? true : car['scheduled'],
          'external_driver_code' => row['driver_code'])
        if fresh
          car['operation'] = row['operation']
          car['room'] = row['freight'] ? 'spot' : row['operation'] == 'as' ? 'as' : row['operation'] == 'vespertina' ? 'vespertina' : row['maps'].first['cities'].start_with?('FOZ') || row['operation'] == 'van' ? 'room2' : 'room1'
          car['departure_time'] = Board::ROOMS.fetch(car['room']).last
          reported = row['driver_code'].present? ? board.members.select { |m| m['role'] == 'driver' && TimeOff::RoutingCsv.driver_code(m['code']) == row['driver_code'] } : []
          person = reported.one? ? reported.first : nil
          if row['freight']
            car['driver'] = nil
            car['external_driver'] = person&.fetch('name', '') || ''
          elsif person && board.eligible?(person, car, 'driver')
            car['driver'] = person['id']
          else
            car['driver'] = nil
          end
        end
        car
      end
      remaining = existing.reject { |car| used.include?(car['key']) || Array(car['maps']).any? }
      remaining.each do |car|
        if car['operation'] == 'route'
          car['scheduled'] = false
          Board::ROLES.each { |role| car[role] = nil }
        end
      end
      # An imported driver occupies one departure; release any old suggestion.
      drivers = imported.filter_map { |c| c['driver'] }
      remaining.each { |car| Board::ROLES.each { |role| car[role] = nil if drivers.include?(car[role]) } }
      [*imported, *remaining]
    end

    private

    def normalize(value) = I18n.transliterate(value.to_s).strip.downcase.gsub(/\s+/, ' ')

    def operation_for(row, plate, code, freight)
      raw = normalize(row['as / rota'])
      return raw == 'as' ? 'as' : 'route' if freight
      special = @board.dimensioning&.standard_plate_by_special_route&.find { |_, item| TimeOff::RoutingCsv.plate(item.plate.placa) == plate }&.first
      return special if special
      people = code.present? ? @board.members.select { |m| m['role'] == 'driver' && TimeOff::RoutingCsv.driver_code(m['code']) == code } : []
      if people.one? && @board.schedule
        type, id = people.first['id'].split(':')
        fixed = @board.schedule.time_off_memberships.on(@board.date).find_by(driver_id: id)&.standard_operation if type == 'driver'
        return fixed if fixed.present?
      end
      return 'van' if normalize(row['veiculo']) == 'van' || raw == 'van' || (people.one? && people.first['cargo'] == 'van')
      return 'vespertina' if raw == 'vespertina'
      return 'as' if raw == 'as'
      raise TimeOff::UpdateDay::InvalidChange, "Operação desconhecida na placa #{plate}." unless raw == 'rota'
      'route'
    end
  end
end
