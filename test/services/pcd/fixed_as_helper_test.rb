require 'test_helper'

class PcdFixedAsHelperTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 10, 2)
    @schedule = TimeOffSchedule.create!(name: 'Equipe AS', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @dimensioning = FleetDimensioning.create!(label: 'Equipe AS', start_date: '2026-10-01', end_date: '2026-10-31', route_quantity: 1, vespertina_quantity: 0, as_quantity: 1, van_quantity: 0)
    drivers(:one).update_columns(promax: '9100')
    @driver = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'FIXO', fixed_weekday: 6, standard_operation: 'as', starts_on: '2026-10-01')
    @helper = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'FIXO', fixed_weekday: 6, standard_operation: 'as', starts_on: '2026-10-01')
    @route_helper = @schedule.time_off_memberships.create!(ajudante: ajudantes(:two), group_code: 'A', starts_on: '2026-10-01')
  end

  test 'initial PCD reserves the fixed AS helper instead of assigning them to a standard route' do
    board = Pcd::Board.new(date: @date)
    as = board.cars.find { |car| car['operation'] == 'as' }
    route = board.cars.find { |car| car['operation'] == 'route' }
    assert_equal 1, as['helper_count']
    assert_equal helper_key, as['helper1']
    assert_equal "helper:#{@route_helper.ajudante_id}", route['helper1']
    assert_equal 2, TimeOff::Demand.new(coverage).metrics[:helper_need]
    assert_equal 1, as_row[:helpers]
    assert_equal 1, as_row[:helper_need]
  end

  test 'AS helper demand starts with the dated membership and special operations stop on weekends' do
    @helper.update!(starts_on: '2026-10-05')
    assert_equal 0, Pcd::Board.new(date: @date).cars.find { |car| car['operation'] == 'as' }['helper_count']
    future = Pcd::Board.new(date: Date.new(2026, 10, 5)).cars.find { |car| car['operation'] == 'as' }
    assert_equal 1, future['helper_count']
    assert_equal helper_key, future['helper1']
    assert Pcd::Board.new(date: Date.new(2026, 10, 3)).cars.all? { |car| car['operation'] == 'route' }
    assert_empty Pcd::Board.new(date: Date.new(2026, 10, 4)).cars
  end

  test 'an unavailable or inactive AS helper opens the helper position without removing its demand' do
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @helper.id, date: @date, status: 'unavailable',
      reason: 'Atestado', expected_revision: -1, user: users(:one))
    as = Pcd::Board.new(date: @date).cars.find { |car| car['operation'] == 'as' }
    assert_equal 1, as['helper_count']
    assert_nil as['helper1']
    assert_equal 1, as_row[:helper_gap]
    ajudantes(:one).update!(active: false)
    as = Pcd::Board.new(date: @date).cars.find { |car| car['operation'] == 'as' }
    assert_equal 1, as['helper_count']
    assert_nil as['helper1']
    assert_equal 1, as_row[:helper_gap]
  end

  test 'saved PCD compositions remain intact when a fixed AS helper is configured later' do
    @helper.update!(standard_operation: nil)
    cars = Pcd::Board.new(date: @date).cars
    as = cars.find { |car| car['operation'] == 'as' }
    assert_equal 0, as['helper_count']
    PcdPlan.create!(date: @date, details: { cars: cars })
    @helper.update!(standard_operation: 'as')
    saved = Pcd::Board.new(date: @date).cars.find { |car| car['operation'] == 'as' }
    assert_equal 0, saved['helper_count']
    assert_nil saved['helper1']
  end

  test 'import and refresh preserve the fixed AS helper and saving does not change the schedule' do
    source = "Data Entrega;Nro do Mapa;AS / Rota;Placa;Carga;Cidades +Entregas;Região +Entregas;Motorista\n02/10/2026;123;AS;AAA1B23;Própria;FOZ;CENTRO;9100\n"
    upload = Struct.new(:original_filename, :io) { def read(length) = io.read(length) }
    preview = Pcd::RoutingCsv.new(file: upload.new('as.csv', StringIO.new(source)), board: Pcd::Board.new(date: @date)).preview
    as = preview[:cars].find { |car| car['operation'] == 'as' }
    assert_equal 1, as['helper_count']
    assert_equal helper_key, as['helper1']
    assert_no_difference(['TimeOffMembership.count', 'TimeOffOverride.count', 'TimeOffChange.count']) do
      Pcd::Save.call(date: @date, user: users(:one), attributes: {
        reason: 'Equipe AS conferida', expected_revision: -1, routing_token: preview[:token], cars: preview[:cars]
      })
    end
    refreshed = Pcd::RoutingCsv.new(file: upload.new('as.csv', StringIO.new(source)), board: Pcd::Board.new(date: @date)).preview
    assert_equal helper_key, refreshed[:cars].find { |car| car['operation'] == 'as' }['helper1']
  end

  private

  def coverage
    TimeOff::Coverage.new(schedule: @schedule, date: @date)
  end

  def as_row
    coverage.rows.find { |row| row[:operation] == 'as' }
  end

  def helper_key
    "helper:#{@helper.ajudante_id}"
  end
end
