require 'test_helper'

class DuVariableAverageReportTest < ActiveSupport::TestCase
  setup do
    @one = Employee.create!(nome: 'Primeira pessoa', matricula: 'AVG-ONE')
    @two = Employee.create!(nome: 'Segunda pessoa', matricula: 'AVG-TWO')
  end

  def closing(person, year:, month:, revision: 1, sector: 'du', **groups)
    VariableClosing.create!(employee: person, user: users(:one), year: year, month: month,
      revision: revision, sector: sector, reason: 'Teste da referência histórica', result: { groups: groups, maps: [] })
  end

  def group(value, maps: 1)
    { valor_total: value, quantidade_mapas: maps }
  end

  def row(person, value, maps: 1)
    { person_key: "employee-#{person.id}", nome: person.nome, matricula: person.matricula, valor_total: value, mapas: maps }
  end

  test 'uses the preceding twelve cycles, latest revisions, zero payments and one driver observation for both cargos' do
    closing(@one, year: 2025, month: 10, motorista: group(9999))
    closing(@one, year: 2025, month: 10, revision: 2, motorista: group(400), van: group(600), ajudante: group(100))
    closing(@two, year: 2025, month: 10, motorista: group(2000), ajudante: group(200))
    closing(@one, year: 2026, month: 9, motorista: group(0), ajudante: group(0))
    closing(@two, year: 2026, month: 9, motorista: group(5000, maps: 0))
    closing(@one, year: 2025, month: 9, motorista: group(50000))
    closing(@one, year: 2026, month: 10, motorista: group(50000))
    closing(@one, year: 2026, month: 11, motorista: group(50000))
    closing(@one, year: 2026, month: 8, sector: 'az', motorista: group(50000))

    report = DuVariableAverageReport.new(year: 2026, month: 10,
      driver_ranking: [row(@one, 500), row(@one, 800), row(@two, 0)], helper_ranking: [row(@one, 150)])
    assert_equal Date.new(2025, 10, 1), report.from
    assert_equal Date.new(2026, 9, 1), report.to
    assert_equal 1000, report.summary(:driver)[:average]
    assert_equal 100, report.summary(:helper)[:average]
    assert_equal 3, report.summary(:driver)[:observations]
    assert_equal 2, report.summary(:driver)[:months]
    assert_equal 2, report.summary(:driver)[:count]
    assert_equal 1300, report.entries(:driver).first[:value]
    assert_equal 300, report.entries(:driver).first[:difference]
    assert_equal :above, report.entries(:driver).first[:position]
    assert_equal :below, report.entries(:driver).last[:position]
    assert_equal [['Motoristas', 1000.0], ['Ajudantes', 100.0]], report.average_chart_data
    assert_equal [[@two.nome, -1000.0]], report.comparison_chart_data(:driver, position: :below)
  end

  test 'does not invent a zero baseline or classify people when history is absent' do
    report = DuVariableAverageReport.new(year: 2026, month: 10,
      driver_ranking: [row(@one, 123)], helper_ranking: [])
    assert_nil report.summary(:driver)[:average]
    assert_equal 0, report.summary(:driver)[:months]
    assert_equal :unavailable, report.entries(:driver).first[:position]
    assert_nil report.entries(:driver).first[:difference]
    assert_empty report.average_chart_data
    assert_empty report.comparison_chart_data(:driver, position: :below)
  end

  test 'compares currency at cent precision and keeps namesakes as separate bars' do
    closing(@one, year: 2026, month: 9, motorista: group('100.004'))
    @two.update!(nome: @one.nome)
    report = DuVariableAverageReport.new(year: 2026, month: 10,
      driver_ranking: [row(@one, '100.001'), row(@two, 130)], helper_ranking: [])
    assert_equal :equal, report.entries(:driver).find { |entry| entry[:key] == "employee-#{@one.id}" }[:position]
    assert_equal [["#{@two.nome} · #{@two.matricula}", 30.0]], report.comparison_chart_data(:driver, position: :above)
  end
end
