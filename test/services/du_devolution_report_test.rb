require 'test_helper'

class DuDevolutionReportTest < ActiveSupport::TestCase
  setup do
    @driver = Employee.create!(nome: 'Motorista da equipe', matricula: 'DEV-DRIVER')
    @driver.change_role!({ sector: 'du', cargo: 'motorista', promax: 'DEV-D', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    @helper = Employee.create!(nome: 'Ajudante da equipe', matricula: 'DEV-HELPER')
    @helper.change_role!({ sector: 'du', cargo: 'ajudante', promax: 'DEV-H', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
  end

  def map(total:, delivered:, **attributes)
    Mapa.new({ data: '10/01/2026', matric_motorista: 'DEV-D', matric_ajudante: 'DEV-H', pdv_total: total, pdv_real: delivered, recarga: 'NAO' }.merge(attributes))
  end

  test 'weights percentages per person across team changes and both helper positions' do
    report = DuDevolutionReport.new([
      map(total: 10, delivered: 9, matric_ajudante_2: 'DEV-H2'),
      map(total: 100, delivered: 95, matric_ajudante: 'DEV-H2', matric_ajudante_2: 'DEV-H'),
      map(total: 4, delivered: 2, data: '11/01/2026'),
      map(total: 500, delivered: 0, recarga: 'SIM'),
      map(total: 100, delivered: nil),
      map(total: 0, delivered: 0),
      map(total: 3, delivered: 4)
    ])

    assert_equal 114, report.general[:total]
    assert_equal 8, report.general[:returned]
    assert_in_delta 8.0 / 114, report.general[:percentage], 0.000001
    assert_equal 3, report.general[:maps]
    assert_equal 3, report.ignored_maps_count
    assert_equal 1, report.ranking(:driver).size
    assert_in_delta 8.0 / 114, report.ranking(:driver).first[:percentage], 0.000001
    assert_equal 2, report.ranking(:helper).size
    assert_equal 2, report.ranking(:helper).last[:maps]
    assert_in_delta 6.0 / 110, report.ranking(:helper).last[:percentage], 0.000001
    assert_equal @driver.nome, report.ranking(:driver).first[:person][:name]
    assert_equal @helper.nome, report.ranking(:helper).first[:person][:name]
    assert_equal @driver.nome, report.ranking_chart_data(:driver).first.first
    assert_equal [['Entregues', 106.0], ['Devolvidos', 8.0]], report.general_chart_data
    assert_equal ['2026-01-10', '2026-01-11'], report.daily_chart_data.keys
    assert_in_delta 100 * 6.0 / 110, report.daily_chart_data['2026-01-10'], 0.000001
    assert_equal 50, report.daily_chart_data['2026-01-11']
  end

  test 'groups maps across a dated change of Promax for the same person' do
    @driver.change_role!({ sector: 'du', cargo: 'motorista', promax: 'DEV-NEW', starts_on: '2026-01-16', reason: 'Novo código' }, user: users(:one))
    report = DuDevolutionReport.new([
      map(total: 10, delivered: 9),
      map(total: 100, delivered: 95, data: '20/01/2026', matric_motorista: 'DEV-NEW')
    ])

    assert_equal 1, report.ranking(:driver).size
    assert_equal 2, report.ranking(:driver).first[:maps]
    assert_equal @driver.nome, report.ranking(:driver).first[:person][:name]
  end

  test 'does not use a current legacy adapter when the DU role did not cover the map date' do
    @driver.change_role!({ sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-02-01', reason: 'Transferência' }, user: users(:one))
    report = DuDevolutionReport.new([map(total: 10, delivered: 8, data: '10/02/2026')])

    assert_equal 'Motorista DEV-D', report.ranking(:driver).first[:person][:name]
  end

  test 'handles an empty period and zero devolution without inventing a percentage or team' do
    empty = DuDevolutionReport.new([])
    assert_nil empty.general[:percentage]
    assert_empty empty.general_chart_data
    assert_empty empty.ranking_chart_data(:driver)

    delivered = DuDevolutionReport.new([map(total: 10, delivered: 10)])
    assert_equal 0, delivered.general[:percentage]
    assert_empty delivered.ranking(:helper)
  end

  test 'van recharges and explicit van corrections count as deliveries using the cargo on the map date' do
    van = Employee.create!(nome: 'Motorista de van', matricula: 'DEV-VAN')
    van.change_role!({ sector: 'du', cargo: 'van', promax: 'DEV-V', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    van.change_role!({ sector: 'du', cargo: 'motorista', promax: 'DEV-V', starts_on: '2026-01-16', reason: 'Promoção' }, user: users(:one))
    report = DuDevolutionReport.new([
      map(total: 10, delivered: 8, matric_motorista: 'DEV-V', recarga: 'SIM'),
      map(total: 100, delivered: 0, matric_motorista: 'DEV-V', recarga: 'SIM', data: '20/01/2026'),
      map(total: 20, delivered: 19, recarga: 'SIM', cargo_override: 'van')
    ])

    assert_equal 30, report.general[:total]
    assert_equal 3, report.general[:returned]
    assert_equal 2, report.general[:maps]
    assert_in_delta 0.1, report.general[:percentage], 0.000001
  end
  test 'counts a helper once when both slots contain the same person' do
    report = DuDevolutionReport.new([
      map(total: 10, delivered: 8, matric_ajudante_2: 'DEV-H'),
      map(total: 20, delivered: 19)
    ])
    helper = report.ranking(:helper).first
    assert_equal 2, helper[:maps]
    assert_equal 30, helper[:total]
    assert_equal 3, helper[:returned]
    assert_in_delta 0.1, helper[:percentage], 0.000001
    assert_equal 2, report.general[:maps]
  end

  test 'keeps namesakes as separate bars with their registrations' do
    other = Employee.create!(nome: @driver.nome, matricula: 'DEV-NAMESAKE')
    other.change_role!({ sector: 'du', cargo: 'motorista', promax: 'DEV-N', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    report = DuDevolutionReport.new([
      map(total: 10, delivered: 8),
      map(total: 100, delivered: 95, matric_motorista: 'DEV-N')
    ])
    assert_equal ["#{@driver.nome} · DEV-DRIVER", "#{other.nome} · DEV-NAMESAKE"], report.ranking_chart_data(:driver).map(&:first)
    assert_equal [20.0, 5.0], report.ranking_chart_data(:driver).map(&:last)
  end

  test 'management alerts can inspect all offenders beyond the chart limit' do
    maps = 14.times.map { |index| map(total: 100, delivered: 90, matric_motorista: "UNKNOWN-#{index}", matric_ajudante: nil) }
    report = DuDevolutionReport.new(maps)
    assert_equal 10, report.ranking(:driver).size
    assert_equal 14, report.ranking(:driver, limit: nil).size
    assert_equal 14, report.unresolved_members.size
  end
end
