require 'test_helper'

class TimeOffRoutingCsvTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 10, 2)
    @schedule = TimeOffSchedule.create!(name: 'Importação', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @dimensioning = FleetDimensioning.create!(label: 'Outubro CSV', start_date: '2026-10-01', end_date: '2026-10-31', route_quantity: 18, vespertina_quantity: 1, as_quantity: 1, van_quantity: 1)
    @driver = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'A', starts_on: @schedule.starts_on)
    @helper = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'A', starts_on: @schedule.starts_on)
  end

  test 'real report imports 17 own vehicles and ignores 6 freight rows without persistence' do
    assert_no_difference(['TimeOffDailyPlan.count', 'TimeOffChange.count', 'Plate.count']) do
      result = preview
      assert_equal 17, result[:metadata]['rows'].size
      assert_equal 6, result[:metadata]['ignored_freight']
      assert_equal 'FML6122', result[:metadata]['rows'].first['plate']
      assert_equal '217', result[:metadata]['rows'].first['driver_code']
      assert_equal %w[179801], result[:metadata]['rows'].first['maps']
      assert_equal 17, result[:assignments].map { |r| r['key'] }.uniq.size
      assert_equal ['route'], result[:metadata]['rows'].map { |row| row['operation'] }.uniq
    end
    assert_equal 18, @dimensioning.reload.route_quantity
  end

  test 'CSV plates follow the crew already assigned to the reported driver' do
    drivers(:one).update_columns(promax: '217')
    result = preview
    assert_equal 'route:0', result[:assignments].find { |r| r['plate'] == 'FML6122' }['key']
    drivers(:one).update_columns(promax: '2')
    result = preview
    assert_equal 'route:0', result[:assignments].find { |r| r['plate'] == 'QJU2428' }['key']
  end

  test 'wrong day malformed file and excess vehicles reject the whole preview' do
    assert_raises(TimeOff::UpdateDay::InvalidChange) { preview(date: @date + 1) }
    assert_raises(TimeOff::UpdateDay::InvalidChange) { preview(file: upload("qualquer;texto\na;b\n")) }
    assert_raises(TimeOff::UpdateDay::InvalidChange) { preview(file: upload('')) }
    @dimensioning.update!(route_quantity: 16)
    assert_raises(TimeOff::UpdateDay::InvalidChange) { preview }
    assert_nil @schedule.time_off_daily_plans.first
  end

  test 'duplicate maps are ignored only when their data agrees and multiple maps share a vehicle' do
    header = "Data Entrega;Nro do Mapa;AS / Rota;Placa;Motorista;Carga\n"
    line = "02/10/2026;123;Rota;AAA1B23;002;Fixa\n"
    result = preview(file: upload(header + line + line + line.sub(';123;', ';124;')))
    assert_equal 1, result[:metadata]['duplicates']
    assert_equal %w[123 124], result[:metadata]['rows'].first['maps']
    assert_equal 1, result[:assignments].size
    assert_raises(TimeOff::UpdateDay::InvalidChange) { preview(file: upload(header + line + line.sub('AAA1B23', 'BBB2C34'))) }
  end

  test 'signed import saves daily plates while a position without a departure does not cause a shortage' do
    result = preview
    cars = imported_cars(result)
    cars.last(4).each { |car| car['scheduled'] = false; TimeOff::Board::ROLES.each { |role| car[role] = nil } }
    assert_difference('TimeOffDailyPlan.count', 1) { save(cars, result[:token]) }
    saved = TimeOff::Board.new(coverage)
    assert_equal 21, saved.cars.size
    assert_equal 17, saved.metrics[:cars]
    assert_equal 16, saved.metrics[:driver_gap]
    assert_equal 16, saved.metrics[:helper_gap]
    assert_equal 17, saved.coverage.details['routing_import']['rows'].size
    assert_equal 'FML6122', saved.cars.first['plate']
    assert_equal 18, @dimensioning.reload.route_quantity
    save(saved.cars)
    assert_equal 'FML6122', TimeOff::Board.new(coverage).cars.first['plate']
    assert @schedule.time_off_changes.last.details['movements'].is_a?(Array)
    next_day = TimeOff::Board.new(coverage(Date.new(2026, 10, 5)))
    assert_nil next_day.coverage.details['routing_import']
    assert_equal 21, next_day.metrics[:cars]
    assert_nil next_day.cars.first['plate']
  end

  test 'forged expired or different day token cannot authorize unregistered plates' do
    result = preview
    cars = imported_cars(result)
    assert_no_difference(['TimeOffDailyPlan.count', 'TimeOffChange.count']) do
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars, 'alterado') }
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars) }
      assert_raises(TimeOff::UpdateDay::InvalidChange) { TimeOff::RoutingCsv.verify(result[:token], schedule: @schedule, date: @date + 1) }
      travel 5.hours do
        assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars, result[:token]) }
      end
    end
  end

  test 'duplicate or inactive plates and crews assigned to inactive departures are rejected' do
    result = preview
    cars = imported_cars(result)
    cars[1]['plate'] = cars[0]['plate']
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars, result[:token]) }
    cars = imported_cars(result)
    Plate.create!(placa: cars[0]['plate'], setor: 'ROTA', tipo: 'Caminhão', active: false)
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars, result[:token]) }
    cars = TimeOff::Board.new(coverage).cars
    cars[0]['scheduled'] = false
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars) }
  end

  private

  def coverage(date = @date)
    TimeOff::Coverage.new(schedule: @schedule, date: date)
  end

  def upload(text)
    Struct.new(:original_filename, :io) do
      def read(length) = io.read(length)
    end.new('roteirizacao.csv', StringIO.new(text))
  end

  def preview(file: nil, date: @date)
    file ||= Rack::Test::UploadedFile.new(Rails.root.join('test/fixtures/files/time_off_routing.csv'), 'text/csv')
    TimeOff::RoutingCsv.new(file: file, coverage: coverage(date)).preview
  end

  def imported_cars(result)
    assignment = result[:assignments].index_by { |row| row['key'] }
    TimeOff::Board.new(coverage).cars.map do |car|
      if (row = assignment[car['key']])
        car['plate'] = row['plate']
      elsif car['operation'] == 'route'
        car['plate'] = nil
        car['scheduled'] = false
        TimeOff::Board::ROLES.each { |role| car[role] = nil }
      end
      car
    end
  end

  def save(cars, token = nil)
    current = coverage
    TimeOff::UpdateBoard.call(schedule: @schedule, date: @date, user: users(:one), attributes: {
      reason: 'Cobertura do dia após revisar o CSV', dimensioning_signature: current.signature,
      expected_revision: current.plan&.lock_version || -1, routing_token: token, cars: cars
    })
  end
end
