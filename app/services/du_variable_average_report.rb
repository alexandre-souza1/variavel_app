class DuVariableAverageReport
  PROFILES = { driver: 'Motoristas', helper: 'Ajudantes' }.freeze
  CARGOS = { driver: %w[motorista van], helper: %w[ajudante] }.freeze
  attr_reader :from, :to

  def initialize(driver_ranking:, helper_ranking:, year:, month:)
    cycle = Date.new(year, month, 1)
    @from = cycle.prev_year
    @to = cycle.prev_month
    history = historical_summary
    @entries = {}
    @summaries = {}
    { driver: driver_ranking, helper: helper_ranking }.each do |profile, ranking|
      people = ranking.select { |row| row[:mapas].to_i.positive? && !row[:valor_total].nil? }
        .group_by { |row| row.fetch(:person_key) }
        .map do |key, rows|
          { key: key, name: rows.first[:nome], registration: rows.first[:matricula],
            value: rows.sum { |row| row[:valor_total].to_d }.round(2), maps: rows.sum { |row| row[:mapas].to_i } }
        end
      total = people.sum { |person| person[:value] }
      average = history.fetch(profile)[:average]
      people.each do |person|
        person[:difference] = average.nil? ? nil : person[:value] - average
        person[:position] = if average.nil?
          :unavailable
        elsif person[:difference].positive?
          :above
        elsif person[:difference].negative?
          :below
        else
          :equal
        end
      end
      names = people.group_by { |person| person[:name] }
      people.each do |person|
        person[:label] = names[person[:name]].many? ? "#{person[:name]} · #{person[:registration]}" : person[:name]
      end
      @entries[profile] = people.sort_by { |person| [person[:name], person[:registration].to_s, person[:key]] }
      @summaries[profile] = history.fetch(profile).merge(count: people.size, total: total,
        below: people.count { |person| person[:position] == :below },
        above: people.count { |person| person[:position] == :above },
        equal: people.count { |person| person[:position] == :equal })
    end
  end

  def entries(profile)
    @entries.fetch(profile)
  end

  def summary(profile)
    @summaries.fetch(profile)
  end

  def average_chart_data
    PROFILES.filter_map do |profile, label|
      average = summary(profile)[:average]
      [label, average.to_f] unless average.nil?
    end
  end

  def comparison_chart_data(profile, position:)
    entries(profile).select { |person| person[:position] == position }
      .sort_by { |person| [position == :below ? person[:difference] : -person[:difference], person[:name], person[:key]] }
      .first(10).map { |person| [person[:label], person[:difference].to_f] }
  end

  private

  def historical_summary
    # Read only the totals from the latest revision of each monthly DU closing.
    # Map snapshots can be large and are deliberately excluded from this query.
    closings = VariableClosing.where(sector: 'du')
      .where('(year, month) >= (?, ?) AND (year, month) <= (?, ?)', from.year, from.month, to.year, to.month)
      .select("DISTINCT ON (employee_id, year, month) employee_id, year, month, result->'groups' AS historical_groups")
      .order(:employee_id, :year, :month, revision: :desc, id: :desc).to_a
    CARGOS.to_h do |profile, cargos|
      observations = closings.filter_map do |closing|
        groups = closing.historical_groups || {}
        values = cargos.filter_map do |cargo|
          group = groups[cargo]
          group['valor_total'].to_d if group && group['quantidade_mapas'].to_i.positive? && !group['valor_total'].nil?
        end
        { value: values.sum.round(2), cycle: [closing.year, closing.month] } if values.any?
      end
      total = observations.sum { |item| item[:value] }
      [profile, { average: observations.any? ? (total / observations.size).round(2) : nil,
        observations: observations.size, months: observations.map { |item| item[:cycle] }.uniq.size }]
    end
  end
end
