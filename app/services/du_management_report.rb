class DuManagementReport
  attr_reader :maps, :drivers, :helpers, :devolution, :averages, :from, :to, :issues

  def initialize(maps:, drivers:, helpers:, devolution:, averages:, from:, to:, partial:, issues: [])
    @maps, @drivers, @helpers = maps, drivers, helpers
    @devolution, @averages = devolution, averages
    @from, @to, @partial, @issues = from, to, partial, issues
  end

  def partial?
    @partial || (from <= Date.current && to > Date.current)
  end

  def total_variable
    (drivers + helpers).sum { |row| row[:valor_total].to_d }
  end

  def charts
    @charts ||= begin
      result = []
      { 'Motoristas' => drivers, 'Ajudantes' => helpers }.each do |label, rows|
        [:top, :bottom].each do |direction|
          sorted = rows.sort_by { |row| [direction == :top ? -row[:valor_total] : row[:valor_total], row[:nome]] }.first(10)
          result << chart("#{direction == :top ? 'Top' : 'Bottom'} 10 #{label} por valor", :bars, sorted.map { |row| [row[:cargo] == 'van' ? "#{row[:nome]} · Van" : row[:nome], row[:valor_total].to_f] }, :currency)
        end
      end
      daily_maps = maps.group_by(&:data_formatada).sort.map { |date, records| [date.iso8601, records.size] }
      result << chart('Mapas por dia', :line, daily_maps, :number)
      result << chart('Devolução geral', :donut, devolution.general_chart_data, :number)
      DuVariableAverageReport::PROFILES.each do |profile, label|
        result << chart("Devolução por #{label.downcase}", :bars, devolution.ranking_chart_data(profile), :percent)
      end
      result << chart('Devolução por dia', :line, devolution.daily_chart_data.to_a, :percent)
      result << chart('Média histórica mensal', :bars, averages.average_chart_data, :currency)
      DuVariableAverageReport::PROFILES.each do |profile, label|
        { below: 'abaixo', above: 'acima' }.each do |position, name|
          result << chart("#{label} #{name} da média histórica", :bars, averages.comparison_chart_data(profile, position: position), :currency)
        end
      end
      result
    end
  end

  def alerts
    result = []
    result << ['Período parcial', 'Os valores acumulados ainda não representam um mês completo. A referência histórica é mensal; diferenças abaixo dela não indicam, por si só, pior desempenho.'] if partial?
    result << ['Sem mapas', 'Não há mapas operacionais no intervalo selecionado. Fechamentos salvos, quando existentes, continuam compondo as remunerações.'] if maps.empty?
    summary = devolution.general
    if summary[:percentage] && summary[:percentage] > MapaRemuneracaoService::DEVOLUTION_LIMIT
      result << ['Devolução geral acima de 3%', "#{percent(summary[:percentage])} de devolução: #{summary[:returned].to_i} de #{summary[:total].to_i} PDVs previstos."]
    end
    DuVariableAverageReport::PROFILES.each do |profile, label|
      offenders = devolution.ranking(profile, limit: nil).select { |row| row[:percentage] > MapaRemuneracaoService::DEVOLUTION_LIMIT }
      if offenders.any?
        names = offenders.first(5).map { |row| "#{row[:person][:name]} (#{percent(row[:percentage])})" }.join('; ')
        result << ["#{label}: devolução acima de 3%", "#{offenders.size} colaboradores. Maiores percentuais: #{names}. Este indicador não determina sozinho a elegibilidade do bônus."]
      end
      history = averages.summary(profile)
      if history[:months] < 12
        result << ["Histórico de #{label.downcase}", "Base disponível: #{history[:months]} de 12 meses, #{history[:observations]} registros de pessoa/mês. #{history[:average].nil? ? 'Sem referência para comparação.' : 'A média usa apenas os fechamentos existentes.'}"]
      end
      if history[:below].positive?
        result << ["#{label} abaixo da referência histórica", "#{history[:below]} de #{history[:count]} colaboradores do período estão abaixo do valor médio mensal histórico. Consulte os valores e diferenças na comparação completa."]
      end
    end
    if devolution.ignored_maps_count.positive?
      result << ['PDVs inconsistentes', "#{devolution.ignored_maps_count} mapas ficaram fora dos gráficos de devolução por PDVs ausentes ou inconsistentes."]
    end
    issues.each { |issue| result << ['Vínculo de colaborador', issue] }
    devolution.unresolved_members.each do |person|
      result << ['Colaborador sem identificação segura', "#{person[:name]}. Este código aparece nos mapas, mas não tem vínculo único vigente; a remuneração precisa ser conferida."]
    end
    zero = (drivers + helpers).count { |row| row[:mapas].to_i.positive? && row[:valor_total].to_d.zero? }
    result << ['Variável zerada', "#{zero} registros de cargo com mapas e variável zerada. Verifique tarifas e dados operacionais."] if zero.positive?
    result.presence || [['Sem alertas pelas regras avaliadas', 'Não foram identificadas ocorrências nas verificações de devolução, cobertura histórica, vínculos e variável zerada.']]
  end

  private

  def chart(title, kind, data, unit)
    { title: title, kind: kind, data: data, unit: unit }
  end

  def percent(value)
    "#{format('%.2f', value * 100).tr('.', ',')}%"
  end
end
