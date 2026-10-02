require 'test_helper'

class TimeOffBoardTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 10, 2)
    @schedule = TimeOffSchedule.create!(name: 'Painel', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @dimensioning = FleetDimensioning.create!(label: 'Painel', start_date: '2026-10-01', end_date: '2026-10-31', route_quantity: 2, vespertina_quantity: 0, as_quantity: 0, van_quantity: 0)
    @driver = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'A', pilot_key: 'A-1', starts_on: @schedule.starts_on)
    @resting = @schedule.time_off_memberships.create!(driver: drivers(:two), group_code: 'E', pilot_key: 'E-1', starts_on: @schedule.starts_on)
    @helper = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'A', pilot_key: 'A-2', starts_on: @schedule.starts_on)
  end

  test 'suggestion preserves titular pairs and leaves resting people in their own pool' do
    assert_equal 2, board.cars.size
    assert_equal @driver.id, board.cars.first['driver']
    assert_equal @helper.id, board.cars.first['helper1']
    assert_equal [@resting.id], board.pools['off'].map(&:id)
    assert_nil board.cars.last['driver']
    ids = board.cars.flat_map { |c| TimeOff::Board::ROLES.map { |role| c[role] } }.compact
    assert_equal ids.uniq, ids
  end

  test 'call up from rest and absence are saved atomically with new driver in the car' do
    cars = board.cars
    cars.first['driver'] = @resting.id
    assert_difference('TimeOffChange.count', 3) do
      save(cars, statuses: [change(@driver, 'unavailable'), change(@resting, 'working')])
    end
    assert_equal @resting.id, board.cars.first['driver']
    assert_equal [@driver.id], board.pools['unavailable'].map(&:id)
    assert_empty board.pools['off'] || []
    assert_equal 'working', @resting.time_off_overrides.last.status
    assert_equal 'unavailable', @driver.time_off_overrides.last.status
    assert @schedule.time_off_changes.last.details['movements'].any? { |m| m.include?('Rota padrão 1 · Motorista') }
  end

  test 'invalid assignment rolls back absence and call up as well as audit' do
    cars = board.cars
    cars.first['driver'] = @helper.id
    assert_no_difference(['TimeOffOverride.count', 'TimeOffChange.count', 'TimeOffDailyPlan.count']) do
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars, statuses: [change(@driver, 'unavailable'), change(@resting, 'working')]) }
    end
    assert_equal 'off', coverage.status(@resting)
    assert_equal 'working', coverage.status(@driver)
  end

  test 'saved empty positions are not filled again and helper count is per car' do
    cars = board.cars
    cars.first['driver'] = nil
    cars.first['helper_count'] = 0
    cars.first['helper1'] = nil
    cars.last['helper_count'] = 2
    cars.last['helper2'] = @helper.id
    save(cars)
    assert_nil board.cars.first['driver']
    assert_equal 0, board.cars.first['helper_count']
    assert_equal @helper.id, board.cars.last['helper2']
    assert_equal [@driver.id], board.pools['working'].map(&:id)
  end

  test 'motorista as helper counts only once and duplicate slots are rejected' do
    cars = board.cars
    cars.first['helper1'] = @driver.id
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars) }
    cars.first['driver'] = nil
    save(cars)
    assert_equal 0, board.metrics[:drivers]
    assert_equal @driver.id, board.cars.first['helper1']
  end

  test 'rejects hidden occupants duplicate cars and incomplete board' do
    cars = board.cars
    cars.first['helper_count'] = 0
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars) }
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save([board.cars.first, board.cars.first]) }
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save([]) }
  end

  test 'absence after a saved board releases only this person and does not reassign everyone' do
    save(board.cars)
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @driver.id, date: @date, status: 'unavailable', reason: 'Atestado', expected_revision: -1, user: users(:one))
    assert_nil board.cars.first['driver']
    assert_equal @helper.id, board.cars.first['helper1']
    assert_equal [@driver.id], board.pools['unavailable'].map(&:id)
  end

  test 'concurrent day adjustment and changed dimensioning reject stale board without partial changes' do
    cars = board.cars
    cars.first['driver'] = @resting.id
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @resting.id, date: @date, status: 'unavailable', reason: 'Atestado', expected_revision: -1, user: users(:one))
    assert_raises(TimeOff::UpdateDay::Conflict) { save(cars, statuses: [change(@resting, 'working')]) }
    assert_nil @schedule.time_off_daily_plans.first
    signature = coverage.signature
    @dimensioning.update!(route_quantity: 3)
    assert_raises(TimeOff::UpdateDay::Conflict) { save(board.cars, signature: signature) }
  end

  test 'car labels use standard plates and plate layout changes invalidate an open draft' do
    signature = coverage.signature
    @dimensioning.fleet_dimensioning_standard_plates.create!(position: 0, plate: plates(:one))
    assert_equal plates(:one).placa, board.cars.first['label']
    assert_raises(TimeOff::UpdateDay::Conflict) { save(board.cars, signature: signature) }
  end

  private

  def coverage
    TimeOff::Coverage.new(schedule: @schedule, date: @date)
  end

  def board
    TimeOff::Board.new(coverage)
  end

  def change(member, status)
    { 'member_id' => member.id, 'status' => status, 'expected_revision' => -1 }
  end

  def save(cars, statuses: [], signature: coverage.signature)
    TimeOff::UpdateBoard.call(schedule: @schedule, date: @date, user: users(:one), attributes: {
      'reason' => 'Remanejamento das equipes do dia', 'dimensioning_signature' => signature,
      'expected_revision' => coverage.plan&.lock_version || -1, 'statuses' => statuses, 'cars' => cars
    })
  end
end
