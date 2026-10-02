require 'test_helper'

class TimeOffRosterTest < ActiveSupport::TestCase
  setup do
    @schedule = TimeOffSchedule.create!(name: 'Piloto', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @member = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'E', starts_on: '2026-10-01')
  end

  test 'rotation reproduces every supplied October date and Sunday DSR' do
    expected = { 'A' => [6, 14, 22, 30], 'B' => [7, 15, 23, 31], 'C' => [8, 16, 24, 26],
      'D' => [1, 9, 17, 19, 27], 'E' => [2, 10, 12, 20, 28], 'F' => [3, 5, 13, 21, 29] }
    expected.each do |group, days|
      actual = (Date.new(2026, 10, 1)..Date.new(2026, 10, 31)).select { |date| @schedule.off_group_on(date) == group }.map(&:day)
      assert_equal days, actual, group
    end
    [4, 11, 18, 25].each do |day|
      assert_equal 'dsr', @schedule.base_status(@member, Date.new(2026, 10, day))
      assert_nil @schedule.off_group_on(Date.new(2026, 10, day))
    end
  end

  test 'six week rotation continues across months and years without resetting' do
    assert_equal 'B', @schedule.off_group_on(Date.new(2026, 11, 2))
    assert_equal 'C', @schedule.off_group_on(Date.new(2026, 11, 3))
    (Date.new(2026, 10, 1)..Date.new(2027, 1, 31)).each do |date|
      expected = @schedule.off_group_on(date)
      expected ? assert_equal(expected, @schedule.off_group_on(date + 42)) : assert_nil(@schedule.off_group_on(date + 42))
    end
    @schedule.update!(recurring: false)
    assert_nil @schedule.base_status(@member, Date.new(2026, 11, 2))
    assert_nil @schedule.off_group_on(Date.new(2026, 9, 30))
  end

  test 'fixed group rests Saturday and Sunday' do
    @member.update!(group_code: 'FIXO', fixed_weekday: 6)
    assert_equal 'off', @schedule.base_status(@member, Date.new(2026, 10, 3))
    assert_equal 'dsr', @schedule.base_status(@member, Date.new(2026, 10, 4))
    assert_equal 'working', @schedule.base_status(@member, Date.new(2026, 10, 2))
  end

  test 'call up a resting driver then restore rotation preserving revision and audit' do
    date = Date.new(2026, 10, 2)
    override = change(date, 'working', -1)
    assert_equal 'working', override.status
    assert_equal 'off', @schedule.base_status(@member, date)
    assert_equal 'working', @schedule.base_status(@member, date + 1)
    assert_equal users(:one), @schedule.time_off_changes.last.user
    assert_equal 'off', @schedule.time_off_changes.last.details['before']
    restored = change(date, 'original', override.lock_version)
    assert_equal 'off', restored.status
    assert_operator restored.lock_version, :>, override.lock_version
    assert_equal true, @schedule.time_off_changes.last.details['restored']
    assert_raises(TimeOff::UpdateDay::Conflict) { change(date, 'unavailable', -1) }
    assert_raises(TimeOff::UpdateDay::Conflict) { change(date, 'unavailable', override.lock_version) }
    assert_equal 'off', restored.reload.status
  end

  test 'absence requires reason and cannot override Sunday or a date outside membership' do
    assert_raises(TimeOff::UpdateDay::InvalidChange) { change(Date.new(2026, 10, 2), 'unavailable', -1, '') }
    assert_raises(TimeOff::UpdateDay::InvalidChange) { change(Date.new(2026, 10, 4), 'working', -1) }
    assert_raises(TimeOff::UpdateDay::InvalidChange) { change(Date.new(2026, 9, 30), 'working', -1) }
    assert_no_difference('TimeOffChange.count') do
      assert_raises(TimeOff::UpdateDay::InvalidChange) { change(Date.new(2026, 10, 2), 'bad-status', -1) }
    end
    assert_equal 'unavailable', change(Date.new(2026, 10, 2), 'unavailable', -1, 'Atestado').status
  end

  test 'group changes preserve past membership and future individual adjustments' do
    date = Date.new(2026, 10, 12)
    original = change(date, 'unavailable', -1, 'Férias')
    next_member = TimeOff::AssignGroup.call(schedule: @schedule, person: drivers(:one), group_code: 'A', starts_on: Date.new(2026, 10, 5), user: users(:one))
    assert_equal Date.new(2026, 10, 4), @member.reload.ends_on
    assert_equal 'off', @schedule.base_status(@member, Date.new(2026, 10, 2))
    assert_nil @schedule.base_status(@member, date)
    assert_equal next_member.id, original.reload.time_off_membership_id
    assert_equal 'unavailable', original.status
    assert_raises(ActiveRecord::RecordInvalid) do
      @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'B', starts_on: '2026-10-10')
    end
    assert_no_difference('TimeOffMembership.count') do
      assert_raises(ActiveRecord::RecordInvalid) do
        TimeOff::AssignGroup.call(schedule: @schedule, person: drivers(:one), group_code: 'invalid', starts_on: Date.new(2026, 10, 20), user: users(:one))
      end
    end
    assert_nil next_member.reload.ends_on
    assert_raises(TimeOff::UpdateDay::InvalidChange) do
      TimeOff::AssignGroup.call(schedule: @schedule, person: drivers(:one), group_code: 'A', starts_on: Date.new(2026, 10, 20), fixed_weekday: 6, user: users(:one))
    end
  end

  test 'pilot setup matches by normalized exact name and is idempotent without creating people' do
    drivers(:two).update_columns(nome: '  adair de almeida  ')
    counts = [Driver.count, Ajudante.count]
    result = TimeOff::PilotSetup.call(schedule: @schedule)
    assert_equal 1, result[:created]
    assert_equal 'A', @schedule.time_off_memberships.find_by(driver: drivers(:two)).group_code
    assert_equal 0, TimeOff::PilotSetup.call(schedule: @schedule)[:created]
    assert_equal counts, [Driver.count, Ajudante.count]
    assert_equal 2, result[:pending].count { |entry| entry['vacancy'] }
  end

  private

  def change(date, status, revision, reason = 'Ajuste operacional')
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @member.id, date: date, status: status,
      reason: reason, expected_revision: revision, user: users(:one))
  end
end
