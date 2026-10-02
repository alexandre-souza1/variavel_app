require 'test_helper'

class TimeOffVacationAndExtrasTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 10, 2)
    @schedule = TimeOffSchedule.create!(name: 'Piloto', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @member = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'E', starts_on: '2026-10-01')
  end

  test 'vacations cover the inclusive period including Sunday and block daily edits and allocation' do
    call_up(@date)
    vacation = create_vacation(@date, @date + 8)
    assert_equal 'vacation', availability.status(@member, @date)
    assert_equal 'vacation', availability.status(@member, Date.new(2026, 10, 4))
    assert_equal 'vacation', availability.status(@member, @date + 8)
    assert_equal 'dsr', availability.status(@member, @date + 9)
    assert_empty extras.dates(@member)
    assert_raises(TimeOff::UpdateDay::InvalidChange) { call_up(@date + 1) }
    FleetDimensioning.create!(label: 'Outubro', start_date: @date.beginning_of_month, end_date: @date.end_of_month, route_quantity: 1)
    coverage = TimeOff::Coverage.new(schedule: @schedule, date: @date)
    board = TimeOff::Board.new(coverage)
    assert_nil board.cars.first['driver']
    assert_equal [@member.id], board.pools['unavailable'].map(&:id)
    assert_equal true, board.state[:members].first[:vacation]
    board.cars.first['driver'] = @member.id
    assert_raises(TimeOff::UpdateDay::InvalidChange) { TimeOff::Board.validate!(coverage, board.cars) }
    assert_equal 'vacation', @schedule.time_off_changes.last.details['action']
    assert_equal users(:one).id, @schedule.time_off_changes.last.user_id
  end

  test 'vacations survive a dated group change and cancellation restores prior adjustments' do
    call_up(@date)
    vacation = create_vacation(@date, @date + 12)
    next_member = TimeOff::AssignGroup.call(schedule: @schedule, person: drivers(:one), group_code: 'A', starts_on: @date + 3, user: users(:one))
    assert_equal 'vacation', availability.status(next_member, @date + 5)
    assert_no_difference('TimeOffChange.count') do
      assert_raises(ActiveRecord::RecordInvalid) { create_vacation(@date + 4, @date + 15, next_member) }
    end
    TimeOff::UpdateVacation.cancel(schedule: @schedule, id: vacation.id, reason: 'Férias reagendadas', user: users(:one))
    assert vacation.reload.cancelled_at
    assert_equal 'working', availability.status(@member.reload, @date)
    assert_equal [@date], extras.dates(next_member)
    assert_equal 'vacation_cancelled', @schedule.time_off_changes.last.details['action']
  end

  test 'invalid periods and empty reasons roll back vacation and audit' do
    assert_no_difference(['TimeOffVacation.count', 'TimeOffChange.count']) do
      assert_raises(ActiveRecord::RecordInvalid) { create_vacation(@date, @date - 1) }
      assert_raises(ActiveRecord::RecordInvalid) { create_vacation(@date - 2, @date) }
      assert_raises(ActiveRecord::RecordInvalid) { TimeOff::UpdateVacation.create(schedule: @schedule, membership_id: @member.id, starts_on: @date, ends_on: @date, reason: '', user: users(:one)) }
    end
    vacation = create_vacation(@date, @date + 2)
    assert_raises(TimeOff::UpdateDay::InvalidChange) { TimeOff::UpdateVacation.cancel(schedule: @schedule, id: vacation.id, reason: '', user: users(:one)) }
    assert_nil vacation.reload.cancelled_at
  end

  test 'extras count each final worked rest day once and reflect restoration absence and dated groups' do
    call_up(@date)
    call_up(@date, 0)
    call_up(@date + 8)
    assert_equal [@date, @date + 8], extras.dates(@member)
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @member.id, date: @date + 8, status: 'original', reason: 'Convocação desfeita', expected_revision: 0, user: users(:one))
    call_up(@date + 10)
    assert_equal [@date, @date + 10], extras.dates(@member)
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @member.id, date: @date + 10, status: 'unavailable', reason: 'Atestado', expected_revision: 0, user: users(:one))
    call_up(@date + 1) # Ordinary working day is not an extra.
    next_member = TimeOff::AssignGroup.call(schedule: @schedule, person: drivers(:one), group_code: 'A', starts_on: @date + 3, user: users(:one))
    assert_equal [@date], extras.dates(next_member)
    assert_equal 1, extras.rows.size
  end

  private

  def create_vacation(first, last, member = @member)
    TimeOff::UpdateVacation.create(schedule: @schedule, membership_id: member.id, starts_on: first, ends_on: last, reason: 'Férias programadas', user: users(:one))
  end

  def call_up(date, revision = -1)
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @member.id, date: date, status: 'working', reason: 'Convocação', expected_revision: revision, user: users(:one))
  end

  def availability
    TimeOff::Availability.new(schedule: @schedule, first: @date.beginning_of_month, last: @date.end_of_month)
  end

  def extras
    TimeOff::Extras.new(schedule: @schedule, month: @date, members: @schedule.time_off_memberships.includes(:driver, :ajudante).to_a, availability: availability)
  end
end
