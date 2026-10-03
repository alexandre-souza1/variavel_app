require 'test_helper'

class TimeOffDailyRoutesTest < ActionDispatch::IntegrationTest
  setup do
    @date = Date.new(2026, 10, 2)
    @schedule = TimeOffSchedule.create!(name: 'Disponibilidade', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @dimensioning = FleetDimensioning.create!(label: 'Outubro', start_date: '2026-10-01', end_date: '2026-10-31', route_quantity: 2, vespertina_quantity: 0, as_quantity: 0, van_quantity: 0)
    @driver = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'A', starts_on: @schedule.starts_on)
    @helper = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'A', starts_on: @schedule.starts_on)
    @resting = @schedule.time_off_memberships.create!(driver: drivers(:two), group_code: 'E', starts_on: @schedule.starts_on)
  end

  test 'day separates working drivers and helpers without assigning teams or plates' do
    get time_off_schedule_path(tab: 'day', date: @date)
    assert_response :success
    assert_select '.time-off-working-roles [data-role="driver"] .time-off-person[data-membership-id=?]', @driver.id
    assert_select '.time-off-working-roles [data-role="helper"] .time-off-person[data-membership-id=?]', @helper.id
    assert_select '.time-off-route-row, .time-off-car, select[name^="helpers_"]', 0
    assert_select '[data-day-driver-gap]', text: '1'
    assert_select '[data-day-helper-gap]', text: '1'
    assert_select '.time-off-column--off .time-off-person[data-membership-id=?]', @resting.id
    assert_select '[data-time-off-editable-value="true"]'
    assert_select 'a[href=?]', pcd_path(date: @date), text: 'PCD do dia'
    assert_select '#time-off-day .time-off-day-navigation a[rel="next"][href=?]', time_off_schedule_path(tab: 'day', date: '2026-10-03')
    assert_no_difference(['PcdPlan.count', 'TimeOffDailyPlan.count']) { get time_off_schedule_path(tab: 'day', date: @date) }
  end

  test 'availability changes fill deficits without creating crew plans' do
    assert_no_difference(['PcdPlan.count', 'TimeOffDailyPlan.count']) do
      patch update_day_time_off_schedule_path, params: { change: { membership_id: @resting.id, date: @date, status: 'working', reason: 'Convocação para completar o dia', expected_revision: -1 } }, as: :json
      assert_response :success
    end
    get time_off_schedule_path(tab: 'day', date: @date)
    assert_select '[data-day-driver-gap]', text: '0'
    assert_select '[data-day-helper-gap]', text: '1'
    assert_select '.time-off-working-roles [data-role="driver"] .time-off-person', 2
    patch update_day_time_off_schedule_path, params: { change: { membership_id: @driver.id, date: @date, status: 'unavailable', reason: 'Atestado recebido', expected_revision: -1 } }, as: :json
    get time_off_schedule_path(tab: 'day', date: @date)
    assert_select '[data-day-driver-gap]', text: '1'
    assert_select '.time-off-column--unavailable .time-off-person[data-membership-id=?]', @driver.id
  end

  test 'PCD determines own demand and freight never inflates pilot shortages' do
    cars = [{ 'key' => 'route:0', 'operation' => 'route', 'helper_count' => 0, 'scheduled' => true }]
    6.times { |i| cars << { 'key' => "freight:#{i}", 'operation' => 'as', 'helper_count' => 0, 'freight' => true, 'scheduled' => true } }
    PcdPlan.create!(date: @date, details: { cars: cars })
    get time_off_schedule_path(tab: 'day', date: @date)
    assert_select '[data-day-driver-gap]', text: '0'
    assert_select '[data-day-helper-gap]', text: '0'
    assert_select '.time-off-shortage-summary', text: /1 saídas próprias previstas/
    assert_select '.time-off-shortage-summary', text: /Saídas e composições salvas no PCD/
    assert_equal 2, @dimensioning.reload.route_quantity
    get time_off_schedule_path(tab: 'day', date: @date + 3)
    assert_select '.time-off-shortage-summary', text: /Referência do dimensionamento/
  end

  test 'filters do not hide global deficits and vacations and inactive people are excluded' do
    @helper.update!(group_code: 'B')
    get time_off_schedule_path(tab: 'day', date: @date, role: 'helper', group: 'B')
    assert_select '.time-off-working-roles .time-off-person', 1
    assert_select '[data-day-driver-gap]', text: '1'
    TimeOff::UpdateVacation.create(schedule: @schedule, membership_id: @driver.id, starts_on: @date, ends_on: @date + 7, reason: 'Férias programadas', user: users(:one))
    ajudantes(:one).update!(active: false)
    get time_off_schedule_path(tab: 'day', date: @date)
    assert_select '[data-day-driver-gap]', text: '2'
    assert_select '[data-day-helper-gap]', text: '2'
    assert_select '.time-off-column--unavailable .time-off-person[data-movable="false"]', 1
    assert_select '.time-off-working-roles .time-off-person', 0
  end

  test 'missing dimensioning and Sunday remain safe and ordinary users cannot edit' do
    @dimensioning.destroy!
    get time_off_schedule_path(tab: 'day', date: @date)
    assert_response :success
    assert_select '.time-off-notice', text: /Sem dimensionamento: não é possível calcular/
    assert_select '.time-off-working-roles .time-off-person', 2
    get time_off_schedule_path(tab: 'day', date: '2026-10-04')
    assert_select '.time-off-panel-heading p', text: /DSR para todos/
    assert_select '.time-off-shortage-summary', 0
    users(:one).update!(role: :user, sector: :fleet)
    get time_off_schedule_path(tab: 'day', date: @date)
    assert_select 'dialog', 0
    patch update_day_time_off_schedule_path, params: { change: { membership_id: @driver.id } }, as: :json
    assert_response :forbidden
  end

  test 'a van deficit remains visible even when enough regular drivers are working' do
    @dimensioning.update!(route_quantity: 1, van_quantity: 1)
    @resting.update!(group_code: 'A')
    get time_off_schedule_path(tab: 'day', date: @date)
    assert_select '[data-day-driver-gap]', text: '1'
    assert_select '.time-off-shortage-summary', text: /falta 1 com cargo Motorista de van/
  end
end
