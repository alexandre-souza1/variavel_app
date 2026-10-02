require 'test_helper'

class TimeOffInactivePeopleTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 10, 2)
    @schedule = TimeOffSchedule.create!(name: 'Piloto', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @driver = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'A', starts_on: @schedule.starts_on)
    @helper = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'A', starts_on: @schedule.starts_on)
    FleetDimensioning.create!(label: 'Outubro', start_date: @date.beginning_of_month, end_date: @date.end_of_month, route_quantity: 1)
  end

  test 'retiring a saved crew removes their cards and empties positions without deleting past plans' do
    initial = coverage
    cars = TimeOff::Board.new(initial).cars
    TimeOff::UpdateBoard.call(schedule: @schedule, date: @date, user: users(:one), attributes: {
      cars: cars, statuses: [], reason: 'Composição antes do desligamento', expected_revision: -1, dimensioning_signature: initial.signature })
    stored = @schedule.time_off_daily_plans.last.details.deep_dup
    drivers(:one).retire!
    ajudantes(:one).retire!
    board = TimeOff::Board.new(coverage)
    assert_empty board.members
    assert_empty board.state[:members]
    assert_empty board.pools
    assert_nil board.cars.first['driver']
    assert_nil board.cars.first['helper1']
    assert_equal stored, @schedule.time_off_daily_plans.last.details
    assert_equal 2, @schedule.time_off_memberships.count
    assert_raises(TimeOff::UpdateDay::InvalidChange) { TimeOff::Board.validate!(coverage, cars) }
    assert_equal 1, @schedule.time_off_changes.count
  end

  test 'archived RH employees are excluded and cannot receive day group or vacation changes' do
    employee = Employee.create!(nome: 'RH arquivado', matricula: 'time-off-rh-archived', active: false)
    drivers(:one).update!(employee: employee)
    assert drivers(:one).active?
    assert_not @driver.reload.active_person?
    assert_not TimeOff::People.active_records(Driver).exists?(drivers(:one).id)
    assert_equal [@helper.id], coverage.members.map(&:id)
    assert_no_difference(['TimeOffChange.count', 'TimeOffMembership.count', 'TimeOffVacation.count', 'TimeOffOverride.count']) do
      assert_raises(TimeOff::UpdateDay::InvalidChange) do
        TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @driver.id, date: @date, status: 'off', reason: 'Página desatualizada', expected_revision: -1, user: users(:one))
      end
      assert_raises(TimeOff::UpdateDay::InvalidChange) do
        TimeOff::AssignGroup.call(schedule: @schedule, person: drivers(:one), group_code: 'B', starts_on: @date, user: users(:one))
      end
      assert_raises(TimeOff::UpdateDay::InvalidChange) do
        TimeOff::UpdateVacation.create(schedule: @schedule, membership_id: @driver.id, starts_on: @date, ends_on: @date + 3, reason: 'Página desatualizada', user: users(:one))
      end
    end
  end

  test 'helper record with an archived RH employee is excluded as well' do
    employee = Employee.create!(nome: 'Ajudante arquivado', matricula: 'time-off-helper-archived', active: false)
    ajudantes(:one).update!(employee: employee)
    assert ajudantes(:one).active?
    assert_not TimeOff::People.active_records(Ajudante).exists?(ajudantes(:one).id)
    assert_equal [@driver.id], @schedule.time_off_memberships.with_active_people.pluck(:id)
    assert_equal [@driver.id], coverage.members.map(&:id)
  end

  private

  def coverage
    TimeOff::Coverage.new(schedule: @schedule, date: @date)
  end
end
