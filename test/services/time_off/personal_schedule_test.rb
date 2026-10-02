require 'test_helper'

class TimeOffPersonalScheduleTest < ActiveSupport::TestCase
  setup do
    @today = Date.new(2026, 10, 2)
    @schedule = TimeOffSchedule.create!(name: 'Piloto', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @member = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'A', starts_on: @schedule.starts_on)
  end

  test 'week and month are calendar periods and only contain this person' do
    @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'E', starts_on: @schedule.starts_on)
    result = personal
    assert result[:available]
    assert_equal Date.new(2026, 9, 28), result[:week_start]
    assert_equal 7, result[:week].size
    assert_nil result[:week].first[:status]
    assert_equal 31, result[:days].size
    assert_equal 'working', result[:days][1][:status]
    assert_equal 'dsr', result[:next_off][:status]
    assert_equal Date.new(2026, 10, 4), result[:next_off][:date]
    assert_equal Date.new(2026, 10, 6), result[:next_group_off][:date]
    assert_equal ['A'], result[:days].filter_map { |day| day[:group] }.uniq
  end

  test 'extra work and individual days off are reflected in the next rest' do
    @member.time_off_overrides.create!(date: '2026-10-03', status: 'off', reason: 'Troca pessoal')
    @member.time_off_overrides.create!(date: '2026-10-06', status: 'working', reason: 'Extra')
    result = personal
    assert_equal Date.new(2026, 10, 3), result[:next_off][:date]
    assert result[:days][2][:adjusted]
    assert_equal 'working', result[:days][5][:status]
    @today = Date.new(2026, 10, 5)
    assert_equal Date.new(2026, 10, 14), personal[:next_group_off][:date]
  end

  test 'vacation takes precedence over DSR and overrides and cancelling restores the schedule' do
    @member.time_off_overrides.create!(date: '2026-10-03', status: 'off', reason: 'Troca pessoal')
    vacation = @schedule.time_off_vacations.create!(time_off_membership: @member, starts_on: '2026-10-03', ends_on: '2026-10-07', reason: 'Dados privados')
    result = personal
    assert_equal 'vacation', result[:days][2][:status]
    assert_equal 'vacation', result[:days][3][:status]
    assert_equal Date.new(2026, 10, 11), result[:next_off][:date]
    refute_includes result.to_json, 'Dados privados'
    vacation.update!(cancelled_at: Time.current)
    assert_equal Date.new(2026, 10, 3), personal[:next_off][:date]
  end

  test 'RH identity follows dated driver and helper memberships including vacation across a change' do
    employee = Employee.create!(nome: 'RH Folgas', matricula: 'RH-FOLGAS')
    drivers(:one).update!(employee: employee)
    ajudantes(:one).update!(employee: employee)
    @member.update!(ends_on: '2026-10-05')
    @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'B', starts_on: '2026-10-06')
    result = personal(employee)
    assert_equal 'B', result[:days][6][:group]
    assert_equal Date.new(2026, 10, 7), result[:next_group_off][:date]
    @schedule.time_off_vacations.create!(time_off_membership: @member, starts_on: '2026-10-04', ends_on: '2026-10-08', reason: 'Férias')
    assert_equal 'vacation', personal(employee)[:days][6][:status]
    assert_equal personal(employee)[:days], personal(ajudantes(:one))[:days]
  end

  test 'fixed Saturday rest includes today while missing weekday remains unknown' do
    @member.update!(group_code: 'FIXO', fixed_weekday: 6)
    @today = Date.new(2026, 10, 3)
    assert_equal @today, personal[:next_off][:date]
    @member.update!(fixed_weekday: nil)
    assert_equal 'pending', personal[:days][2][:status]
    assert_nil personal[:next_group_off]
    assert_equal Date.new(2026, 10, 4), personal[:next_off][:date]
  end

  test 'missing schedule enrollment nil person and inactive people are safe and do not presume rest' do
    [nil, Employee.new, drivers(:two), ajudantes(:one)].each do |person|
      result = personal(person)
      assert_not result[:available]
      assert_nil result[:next_off]
      assert result[:days].all? { |day| day[:status].nil? }
    end
    drivers(:one).update!(active: false)
    assert_not personal[:available]
    drivers(:one).update!(active: true, employee: Employee.create!(nome: 'Arquivado', matricula: 'RH-INATIVO', active: false))
    assert_not personal[:available]
    @member.destroy!
    @schedule.reload.destroy!
    assert_not personal[:available]
  end

  test 'expired memberships and finite schedules do not extend future rest' do
    @schedule.update!(recurring: false)
    @today = Date.new(2026, 11, 1)
    result = personal
    assert_nil result[:next_off]
    assert result[:days].all? { |day| day[:status].nil? }
    @schedule.update!(recurring: true)
    @member.update!(ends_on: '2026-10-31')
    assert_nil personal[:next_off]
  end

  test 'month selection is separate from this week and invalid input falls back safely' do
    result = personal(drivers(:one), month: '2026-11')
    assert_equal Date.new(2026, 11, 1), result[:month]
    assert_equal 30, result[:days].size
    assert_equal Date.new(2026, 9, 28), result[:week_start]
    assert_equal Date.new(2026, 10, 1), personal(drivers(:one), month: 'bad-date')[:month]
    assert_equal Date.new(2026, 10, 1), personal(drivers(:one), month: '0000-01')[:month]
  end

  private

  def personal(person = drivers(:one), month: nil)
    TimeOff::PersonalSchedule.new(person: person, today: @today, month: month).call
  end
end
