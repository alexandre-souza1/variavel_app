require 'test_helper'

class GasolaTest < ActiveSupport::TestCase
  def row(**changes)
    { 'id' => 'gasola-test', 'matricula' => 'RH-GASOLA', 'placa' => 'AAA-1234',
      'combustivel' => 'dieselS10', 'categoria' => 'veículo', 'status' => 'CONCLUDED',
      'dataConclusao' => '21/08/2026 10:00', 'totalLitros' => 100,
      'kmRodado' => 400, 'metaKmPorLitro' => 4 }.merge(changes.stringify_keys)
  end

  def sync(rows, from: Time.zone.local(2026, 8, 21), to: Time.zone.local(2026, 9, 21))
    client = Object.new
    calls = []
    client.define_singleton_method(:supplies) { |**args| calls << args; rows }
    Gasola::Sync.new(client: client).call(from: from, to: to)
    calls
  end

  def report
    Gasola::ConsumptionReport.new(registration: 'RH-GASOLA', from: Date.new(2026, 8, 21), to: Date.new(2026, 9, 20))
  end

  test 'splits 31 day periods without gaps and updates repeated IDs' do
    calls = sync([row])
    assert_equal 2, calls.size
    assert_equal calls[0][:to], calls[1][:from]
    assert calls.all? { |call| call[:to] - call[:from] <= 30.days }
    sync([row(kmRodado: 500)])
    assert_equal 1, GasolaSupply.where(external_id: 'gasola-test').count
    assert_equal 500, report.totals[:distance]
    assert_equal Time.zone.local(2026, 8, 21, 10), report.records.first.concluded_at
  end

  test 'weighted average and goal exclude ARLA other people and invalid values' do
    sync([row, row(id: 'second', totalLitros: 50, kmRodado: 100, metaKmPorLitro: 2, placa: 'BBB-1234'),
      row(id: 'arla', combustivel: 'arla'), row(id: 'other', matricula: 'OTHER'),
      row(id: 'missing', kmRodado: nil), row(id: 'zero', totalLitros: 0),
      row(id: 'cancelled', status: 'CANCELLED'), row(id: 'forklift', categoria: 'empilhadeira')])
    totals = report.totals
    assert_equal 4, totals[:count]
    assert_equal 2, totals[:excluded]
    assert_equal 150, totals[:liters]
    assert_in_delta 500.0 / 150, totals[:average], 0.00001
    assert_in_delta 500.0 / 150, totals[:goal], 0.00001
    assert totals[:achieved]
    assert_equal 2, report.by_plate.size
  end

  test 'missing goal is not presented as zero and date bounds are local' do
    sync([row(metaKmPorLitro: nil), row(id: 'before', dataConclusao: '20/08/2026 23:59'),
      row(id: 'last', dataConclusao: '20/09/2026 23:59'), row(id: 'after', dataConclusao: '21/09/2026 00:00')])
    assert_nil report.totals[:goal]
    assert_equal 2, report.totals[:count]
  end

  test 'failure leaves existing data and successful update time unchanged' do
    sync([row])
    before = GasolaSyncRun.count
    assert_raises(Gasola::Client::Error) { sync([row(kmRodado: 900), row(id: 'bad', dataConclusao: 'invalid')]) }
    assert_equal before, GasolaSyncRun.count
    assert_equal 400, report.totals[:distance]
  end

  test 'persists API emission values including zero without inventing missing emissions' do
    sync([row(emissaoCo2: 268, emissaoCo2Meta: 300, impactoCo2: -32), row(id: 'no-co2')])
    supply = GasolaSupply.find_by!(external_id: 'gasola-test')
    assert_equal 268, supply.co2_emission
    assert_equal 300, supply.co2_goal
    assert_equal(-32, supply.co2_impact)
    assert_nil GasolaSupply.find_by!(external_id: 'no-co2').co2_emission
    sync([row(emissaoCo2: 0)])
    assert_equal 0, supply.reload.co2_emission
  end

  test 'default range includes current and previous closing periods' do
    assert_equal Time.zone.local(2026, 8, 21), Gasola::Sync.default_from(Date.new(2026, 9, 23))
    assert_equal Time.zone.local(2026, 7, 21), Gasola::Sync.default_from(Date.new(2026, 9, 20))
  end
end
