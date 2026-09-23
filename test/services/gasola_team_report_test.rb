require 'test_helper'

class GasolaTeamReportTest < ActiveSupport::TestCase
  setup do
    @from, @to = Date.new(2026, 8, 21), Date.new(2026, 9, 20)
    Employee.create!(nome: 'Motorista do painel', matricula: 'TEAM-A')
    supply('one', registration: 'TEAM-A', distance: 400, liters: 100, co2_emission: 268)
    supply('two', registration: 'TEAM-B', distance: 100, liters: 50, co2_emission: nil)
    supply('zero', registration: 'TEAM-A', distance: 50, liters: 10, co2_emission: 0)
    supply('arla', registration: 'TEAM-A', fuel: 'arla', co2_emission: 1000)
    supply('outside', concluded_at: Time.zone.local(2026, 9, 21), co2_emission: 1000)
  end

  def supply(id, **attributes)
    GasolaSupply.create!({ external_id: "team-#{id}", registration: 'TEAM-A', plate: 'ABC-1234',
      concluded_at: Time.zone.local(2026, 9, 1), status: 'CONCLUDED', category: 'veículo', fuel: 'dieselS10',
      liters: 100, distance: 300, goal: 4 }.merge(attributes))
  end

  def report(**filters)
    Gasola::TeamReport.new(from: @from, to: @to, **filters)
  end

  test 'weighted team average and emissions coverage exclude ARLA and outside dates' do
    assert_equal 3, report.totals[:count]
    assert_in_delta 550.0 / 160, report.totals[:average], 0.00001
    assert_equal({ count: 2, missing: 1, total: 268.to_d, average: 134.to_d }, report.emissions)
    assert_equal 2, report.by_driver.size
    assert_equal 'Motorista do painel', report.name('TEAM-A')
    assert_equal 'Sem cadastro vinculado', report.name('TEAM-B')
  end

  test 'filters apply consistently to totals charts emissions and driver rows' do
    filtered = report(registration: 'TEAM-B', plate: 'ABC-1234', fuel: 'dieselS10')
    assert_equal 1, filtered.records.size
    assert_equal 2, filtered.totals[:average]
    assert_nil filtered.emissions[:average]
    assert_equal ['TEAM-B'], filtered.by_driver.map { |row| row[:registration] }
    assert_equal({ '2026-09-01' => 2.0 }, filtered.daily_average)
    assert_empty report(plate: 'NONE').records
  end
end
