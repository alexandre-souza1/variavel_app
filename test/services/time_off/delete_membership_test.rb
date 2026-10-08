require 'test_helper'

class TimeOffDeleteMembershipTest < ActiveSupport::TestCase
  setup do
    @schedule = TimeOffSchedule.create!(name: 'Escala', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @first = member('A', '2026-10-01', '2026-10-06')
    @middle = member('B', '2026-10-07', '2026-10-11')
    @last = member('A', '2026-10-12', nil)
  end

  test 'removing mistaken integration periods preserves the actual start and its holiday adjustment' do
    override = adjustment(@last, '2026-10-12', 'off')
    original_audit = @schedule.time_off_changes.last
    assert_no_difference(['TimeOffMembership.count', 'TimeOffOverride.count']) do
      assert_difference('TimeOffMembership.active.count', -2) do
        assert_difference('TimeOffChange.count', 2) { remove(@first); remove(@middle) }
      end
    end
    assert_equal [@last.id], @schedule.time_off_memberships.pluck(:id)
    assert_empty @schedule.time_off_memberships.on(Date.new(2026, 10, 8))
    assert_nil @schedule.base_status(@first.reload, Date.new(2026, 10, 1))
    assert_equal Date.new(2026, 10, 12), @last.reload.starts_on
    assert_nil @last.ends_on
    assert_equal @last.id, override.reload.time_off_membership_id
    assert_equal 'off', TimeOff::Availability.new(schedule: @schedule, first: override.date).status(@last, override.date)
    assert TimeOffChange.exists?(original_audit.id)
    assert_equal 'group_deleted', @schedule.time_off_changes.last.details['action']
    assert_equal users(:one), @schedule.time_off_changes.last.user
  end

  test 'deleting a middle or last period leaves the other dates unchanged and archives its adjustments' do
    override = adjustment(@middle, '2026-10-09')
    original_audit = @schedule.time_off_changes.last
    remove(@middle)
    assert_equal Date.new(2026, 10, 6), @first.reload.ends_on
    assert_equal Date.new(2026, 10, 12), @last.reload.starts_on
    assert_empty @schedule.time_off_memberships.on(override.date)
    assert TimeOffOverride.exists?(override.id)
    assert TimeOffChange.exists?(original_audit.id)
    archived = @schedule.time_off_changes.last.details['archived_adjustments'].sole
    assert_equal '2026-10-09', archived['date']
    assert_equal 'Ajuste anterior à exclusão', archived['reason']
    remove(@last)
    assert_equal Date.new(2026, 10, 6), @first.reload.ends_on
    assert_nil @last.reload.ends_on
  end

  test 'vacations survive cancellation for the person including a restricted personal schedule' do
    vacation = @schedule.time_off_vacations.create!(time_off_membership: @first, starts_on: '2026-10-12', ends_on: '2026-10-16', reason: 'Férias')
    remove(@first)
    scope = @schedule.time_off_memberships.for_person(ajudantes(:one))
    availability = TimeOff::Availability.new(schedule: @schedule, first: Date.new(2026, 10, 12), memberships: scope)
    assert_equal 'vacation', availability.status(@last, Date.new(2026, 10, 12))
    assert_equal @first.id, vacation.reload.time_off_membership_id
    other = TimeOff::Availability.new(schedule: @schedule, first: Date.new(2026, 10, 12), memberships: @schedule.time_off_memberships.for_person(ajudantes(:two)))
    assert_nil other.vacation(@last, Date.new(2026, 10, 12))
  end

  test 'cancelled open memberships release pilot slots and allow a new assignment to the same person' do
    @last.update!(pilot_key: 'old-slot')
    [@first, @middle, @last].each { |period| remove(period) }
    replacement = TimeOff::AssignGroup.call(schedule: @schedule, person: ajudantes(:one), group_code: 'B', starts_on: Date.new(2026, 10, 12), user: users(:one))
    assert_equal [replacement.id], @schedule.time_off_memberships.with_active_people.pluck(:id)
    assert_nil @last.reload.pilot_key
    assert_equal 'old-slot', @schedule.time_off_changes.where("details->>'action' = 'group_deleted'").last.details['before']['pilot_key']
    assert_empty TimeOffMembership.on(Date.new(2026, 10, 8))
    assert_equal [replacement.id], TimeOffMembership.during(Date.new(2026, 10, 1), Date.new(2026, 10, 31)).pluck(:id)
  end

  test 'blank reasons stale pages repeated deletions and foreign schedules cannot delete a period' do
    assert_raises(TimeOff::UpdateDay::InvalidChange) { remove(@middle, reason: '') }
    assert_raises(TimeOff::UpdateDay::Conflict) { remove(@middle, expected_updated_at: 'stale') }
    other = TimeOffSchedule.create!(name: 'Outra', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28')
    assert_raises(ActiveRecord::RecordNotFound) { remove(@middle, schedule: other) }
    assert_nil @middle.reload.cancelled_at
    assert_equal 0, @schedule.time_off_changes.count
    remove(@middle)
    assert_raises(ActiveRecord::RecordNotFound) { remove(@middle) }
    assert_equal 1, @schedule.time_off_changes.count
  end

  private

  def member(group, first, last)
    @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: group, starts_on: first, ends_on: last)
  end

  def remove(period, **options)
    TimeOff::DeleteMembership.call(**{ schedule: @schedule, membership_id: period.id, reason: 'Em integração; inicia somente em 12/10', expected_updated_at: period.updated_at.iso8601(6), user: users(:one) }.merge(options))
  end

  def adjustment(period, date, status = 'unavailable')
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: period.id, date: Date.iso8601(date), status: status, reason: 'Ajuste anterior à exclusão', expected_revision: -1, user: users(:one))
  end
end
