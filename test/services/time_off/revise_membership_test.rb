require 'test_helper'

class TimeOffReviseMembershipTest < ActiveSupport::TestCase
  setup do
    @schedule = TimeOffSchedule.create!(name: 'Piloto', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @member = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'A', starts_on: '2026-10-08')
  end

  test 'a mistaken future start is corrected on the same membership and audited' do
    assert_no_difference('TimeOffMembership.count') do
      assert_difference('TimeOffChange.count', 1) { revise(starts_on: Date.new(2026, 10, 14)) }
    end
    assert_equal Date.new(2026, 10, 14), @member.reload.starts_on
    assert_nil @schedule.base_status(@member, Date.new(2026, 10, 13))
    assert_equal 'off', @schedule.base_status(@member, Date.new(2026, 10, 14))
    change = @schedule.time_off_changes.last
    assert_equal 'group_corrected', change.details['action']
    assert_equal '2026-10-08', change.details['before']['starts_on']
    assert_equal '2026-10-14', change.details['after']['starts_on']
    assert_equal 'Início lançado errado', change.details['reason']
    assert_equal users(:one), change.user
  end

  test 'postponing a group change restores the previous period and moves adjustments while preserving vacations' do
    previous = previous_member
    removed_day = adjustment(@member, '2026-10-09')
    retained_day = adjustment(@member, '2026-10-15')
    vacation = @schedule.time_off_vacations.create!(time_off_membership: @member, starts_on: '2026-10-10', ends_on: '2026-10-16', reason: 'Férias programadas')
    revise(starts_on: Date.new(2026, 10, 14))
    assert_equal Date.new(2026, 10, 13), previous.reload.ends_on
    assert_equal previous.id, removed_day.reload.time_off_membership_id
    assert_equal @member.id, retained_day.reload.time_off_membership_id
    assert_equal 'unavailable', removed_day.status
    assert_equal @member.id, vacation.reload.time_off_membership_id
    availability = TimeOff::Availability.new(schedule: @schedule, first: Date.new(2026, 10, 9), last: Date.new(2026, 10, 16))
    assert_equal 'unavailable', availability.status(previous, Date.new(2026, 10, 9))
    assert_equal 'vacation', availability.status(previous, Date.new(2026, 10, 10))
    assert_equal 'vacation', availability.status(@member, Date.new(2026, 10, 15))
    assert_equal '2026-10-07', @schedule.time_off_changes.last.details['previous_before']['ends_on']
    assert_equal '2026-10-13', @schedule.time_off_changes.last.details['previous_after']['ends_on']
  end

  test 'bringing a group change forward transfers adjustments from the shortened previous period' do
    previous = previous_member
    override = adjustment(previous, '2026-10-06')
    revise(starts_on: Date.new(2026, 10, 5))
    assert_equal Date.new(2026, 10, 4), previous.reload.ends_on
    assert_equal @member.id, override.reload.time_off_membership_id
    assert_equal 'unavailable', TimeOff::Availability.new(schedule: @schedule, first: override.date).status(@member.reload, override.date)
  end

  test 'adjustments on dates removed from the first membership are archived without erasing original audits' do
    override = adjustment(@member, '2026-10-09')
    original_audit = @schedule.time_off_changes.last
    retained = adjustment(@member, '2026-10-15')
    assert_difference('TimeOffOverride.count', -1) { revise(starts_on: Date.new(2026, 10, 14)) }
    assert_not TimeOffOverride.exists?(override.id)
    assert TimeOffChange.exists?(original_audit.id)
    archived = @schedule.time_off_changes.last.details['archived_adjustments'].sole
    assert_equal '2026-10-09', archived['date']
    assert_equal 'unavailable', archived['status']
    assert_equal 'Ajuste registrado antes da correção', archived['reason']
    assert_equal @member.id, retained.reload.time_off_membership_id
  end

  test 'a gap before a membership stays a gap when its start is corrected' do
    previous = previous_member
    previous.update!(ends_on: '2026-10-03')
    revise(starts_on: Date.new(2026, 10, 14))
    assert_equal Date.new(2026, 10, 3), previous.reload.ends_on
    assert_empty @schedule.time_off_memberships.on(Date.new(2026, 10, 9))
  end

  test 'corrections cannot cross another period or the schedule boundary' do
    previous = previous_member
    @member.update!(ends_on: '2026-10-19')
    @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'C', starts_on: '2026-10-20')
    [Date.new(2026, 10, 1), Date.new(2026, 10, 21), Date.new(2026, 9, 30)].each do |date|
      assert_no_difference('TimeOffChange.count') do
        assert_raises(TimeOff::UpdateDay::InvalidChange) { revise(starts_on: date) }
      end
    end
    assert_equal Date.new(2026, 10, 8), @member.reload.starts_on
    assert_equal Date.new(2026, 10, 7), previous.reload.ends_on
  end

  test 'invalid group rolls back both periods and adjustments' do
    previous = previous_member
    override = adjustment(previous, '2026-10-06')
    assert_no_difference(['TimeOffChange.count', 'TimeOffOverride.count']) do
      assert_raises(ActiveRecord::RecordInvalid) { revise(starts_on: Date.new(2026, 10, 5), group_code: 'invalid') }
    end
    assert_equal Date.new(2026, 10, 7), previous.reload.ends_on
    assert_equal Date.new(2026, 10, 8), @member.reload.starts_on
    assert_equal previous.id, override.reload.time_off_membership_id
  end

  test 'correcting the group releases an initial pilot slot and clears fixed operation fields' do
    @member.update!(group_code: 'FIXO', fixed_weekday: 6, standard_operation: 'vespertina', pilot_key: 'mistaken-slot')
    revise(group_code: 'B')
    assert_equal 'B', @member.reload.group_code
    assert_nil @member.fixed_weekday
    assert_nil @member.standard_operation
    assert_nil @member.pilot_key
    assert_equal 'mistaken-slot', @schedule.time_off_changes.last.details['before']['pilot_key']
  end

  test 'blank reasons no changes inactive people and stale pages do not change the membership' do
    assert_raises(TimeOff::UpdateDay::InvalidChange) { revise(reason: '') }
    assert_raises(TimeOff::UpdateDay::InvalidChange) { revise }
    assert_raises(TimeOff::UpdateDay::Conflict) { revise(starts_on: Date.new(2026, 10, 14), expected_updated_at: 'stale') }
    ajudantes(:one).update!(active: false)
    assert_raises(TimeOff::UpdateDay::InvalidChange) { revise(starts_on: Date.new(2026, 10, 14)) }
    assert_equal Date.new(2026, 10, 8), @member.reload.starts_on
    assert_equal 0, @schedule.time_off_changes.count
  end

  private

  def revise(**options)
    TimeOff::ReviseMembership.call(**{ schedule: @schedule, membership_id: @member.id,
      starts_on: @member.starts_on, group_code: @member.group_code, reason: 'Início lançado errado',
      expected_updated_at: @member.updated_at.iso8601(6), user: users(:one) }.merge(options))
  end

  def previous_member
    @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'E', starts_on: '2026-10-01', ends_on: '2026-10-07')
  end

  def adjustment(member, date)
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: member.id, date: Date.iso8601(date), status: 'unavailable',
      reason: 'Ajuste registrado antes da correção', expected_revision: -1, user: users(:one))
  end
end
