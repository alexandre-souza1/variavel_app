require 'test_helper'

class TimeOffSchedulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @schedule = TimeOffSchedule.create!(name: 'Piloto', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @member = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'E', starts_on: '2026-10-01')
  end

  test 'calendar and day render separately and preserve filters in navigation' do
    get time_off_schedule_path(date: '2026-10-02')
    assert_response :success
    assert_select '.time-off-calendar tbody tr', 1
    assert_select 'turbo-frame#time-off-calendar-content[data-turbo-action="advance"]', 1
    assert_select '.time-off-day-link[data-turbo-frame="_top"]', 7
    assert_select '.time-off-board', 0
    assert_select 'dialog', 0
    assert_select '.time-off-tabs a', 4
    assert_select '.time-off-tabs a', text: 'Grupos', count: 0
    assert_select '.time-off-group-legend .time-off-group-summary', 7
    assert_select '#time-off-settings .time-off-membership-form', 1
    assert_select '.time-off-tabs a[aria-current="page"]', text: 'Calendário'
    assert_select 'a.time-off-day-link[href=?]', time_off_schedule_path(tab: 'day', date: '2026-10-02')
    get time_off_schedule_path(tab: 'day', date: '2026-10-02', group: 'E')
    assert_response :success
    assert_select '.time-off-calendar', 0
    assert_select '#time-off-groups', 0
    assert_select '.time-off-history', 0
    assert_select '.time-off-column--off .time-off-person', 1
    assert_select 'dialog', 1
    assert_select '.time-off-tabs a[aria-current="page"]', text: 'Escala do dia'
    assert_select '.time-off-tabs a[href=?]', time_off_schedule_path(tab: 'history', date: '2026-10-02', group: 'E')
    get time_off_schedule_path(tab: 'day', date: '2026-10-02', role: 'helper')
    assert_response :success
    assert_select '.time-off-person', 0
  end

  test 'changing the month resets selected date to a day inside that month' do
    get time_off_schedule_path(tab: 'day', month: '2026-11', date: '2026-10-02')
    assert_response :success
    assert_select 'input[name="change[date]"][value="2026-11-01"]'
  end

  test 'daily arrows cross month and year boundaries while retaining tab and filters' do
    %w[day history].each do |tab|
      [['2026-10-31', 'next', '2026-11-01'], ['2027-01-01', 'prev', '2026-12-31']].each do |date, direction, destination|
        get time_off_schedule_path(tab: tab, date: date, role: 'helper', group: 'A', calendar_period: 'month', page: 2)
        assert_response :success
        assert_select 'input[type="date"][name="date"]', 0
        link = css_select(".time-off-day-navigation a[rel='#{direction}']").first
        assert_equal time_off_schedule_path(tab: tab, date: destination, role: 'helper', group: 'A', calendar_period: 'month', page: '2'), link['href']
        get link['href']
        assert_response :success
        assert_equal destination, request.params['date']
        assert_select ".time-off-tabs a[aria-current='page'][href*='tab=#{tab}']", 1
        assert_select '.time-off-day-navigation a[rel="next"]', 1
        assert_select '.time-off-day-navigation a[rel="prev"]', 1
        if tab == 'day'
          assert_select '.time-off-filters input[type="hidden"][name="date"][value=?]', destination
          assert_select '.time-off-filters input[type="hidden"][name="month"][value=?]', destination[0, 7]
        else
          assert_select '.time-off-filters', 0
        end
      end
    end
  end

  test 'normal navigation does not report valid page filters as unpermitted parameters' do
    events = []
    subscriber = ->(*args) { events << ActiveSupport::Notifications::Event.new(*args).payload }
    previous_action = ActionController::Parameters.action_on_unpermitted_parameters
    ActionController::Parameters.action_on_unpermitted_parameters = :log
    ActiveSupport::Notifications.subscribed(subscriber, 'unpermitted_parameters.action_controller') do
      get time_off_schedule_path(date: '2026-10-02', tab: 'calendar', month: '2026-10',
        calendar_period: '2026-10-08', page: 1, role: 'driver', group: 'E', settings: '1')
      assert_response :success
      assert_empty events
      assert_select '.time-off-tabs a[href=?]', time_off_schedule_path(tab: 'day', date: '2026-10-02',
        calendar_period: '2026-10-08', page: '1', role: 'driver', group: 'E')
      assert_select '.time-off-filters input[name="calendar_period"][value="2026-10-08"]'

      get time_off_schedule_path(date: '2026-10-02', tab: 'day', calendar_period: '2026-10-08', page: 1)
      assert_response :success
      assert_empty events
      assert_select '.time-off-filters input[name="calendar_period"][value="2026-10-08"]'

      patch update_day_time_off_schedule_path, params: { change: { membership_id: @member.id,
        date: '2026-10-02', status: 'working', reason: 'Convocação', expected_revision: -1, unexpected: 'ignored' } }, as: :json
      assert_response :success
      assert_equal [['unexpected']], events.map { |event| event[:keys] }
    end
  ensure
    ActionController::Parameters.action_on_unpermitted_parameters = previous_action
  end

  test 'calendar periods match the prototype and stop at the end of the month' do
    TimeOff::UpdateVacation.create(schedule: @schedule, membership_id: @member.id, starts_on: Date.new(2026, 10, 30), ends_on: Date.new(2026, 11, 2), reason: 'Férias na virada do mês', user: users(:one))
    get time_off_schedule_path(date: '2026-10-02')
    assert_response :success
    assert_select '.time-off-day-link', 7
    assert_select '.time-off-day-link strong', text: '01'
    assert_select '.time-off-day-link strong', text: '07'
    assert_equal ['01–07', '08–14', '15–21', '22–28', '29–31', 'Mês inteiro'], css_select('.time-off-period-picker button').map(&:text)
    assert_select '.time-off-period-picker button[aria-pressed="true"][value="2026-10-01"]', 1
    assert_select '.time-off-group-dates a', text: '30/10', count: 1
    get time_off_schedule_path(date: '2026-10-30', month: '2026-10', calendar_period: '2026-10-29')
    assert_select '.time-off-day-link', 3
    assert_select '.time-off-day-link strong', text: '29'
    assert_select '.time-off-day-link strong', text: '31'
    assert_select '.time-off-cell--vacation', 2
    assert_select '.time-off-calendar-pagination', text: /1–1 de 1 colaboradores/
    assert_select '.time-off-panel-heading a[href=?]', time_off_schedule_path(tab: 'calendar', date: '2026-11-01', month: '2026-11', calendar_period: '2026-11-01', page: 1), text: 'Próximo mês →'
    assert_select '.time-off-day-link[href=?]', time_off_schedule_path(tab: 'day', date: '2026-10-31', calendar_period: '2026-10-29')
    get time_off_schedule_path(month: '2026-10', date: '2026-10-02', calendar_period: 'month')
    assert_select '.time-off-day-link', 31
    assert_select '.time-off-cell--vacation', 2
    assert_select '.time-off-period-picker button[aria-pressed="true"][value="month"]', 1
  end

  test 'calendar pagination respects filters without paginating the day or group legend' do
    17.times do |i|
      employee = Employee.create!(nome: "Participante #{i.to_s.rjust(2, '0')}", matricula: "calendar-pagination-#{i}")
      driver = Driver.create!(employee: employee, nome: employee.nome, matricula: employee.matricula, promax: "calendar-#{i}")
      @schedule.time_off_memberships.create!(driver: driver, group_code: 'E', starts_on: @schedule.starts_on)
    end
    helper = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'E', starts_on: @schedule.starts_on)
    get time_off_schedule_path(date: '2026-10-02', calendar_period: '2026-10-01', role: 'driver', group: 'E')
    assert_select '.time-off-calendar tbody tr', 12
    assert_select '.time-off-calendar-pagination', text: /1–12 de 18 colaboradores/
    assert_select '.time-off-group-summary', text: /Grupo E19 no dia/
    assert_select '.time-off-calendar-actions button[disabled="disabled"]', text: 'Anterior'
    assert_select '.time-off-calendar-actions button[name="page"][value="2"]:not([disabled])', text: 'Próxima'
    assert_select '.time-off-calendar-actions input[name="role"][value="driver"]', 1
    assert_select '.time-off-calendar-actions input[name="group"][value="E"]', 1
    assert_select '.time-off-calendar-actions input[name="calendar_period"][value="2026-10-01"]', 1
    first_ids = css_select('.time-off-calendar tbody th strong').map(&:text)
    get time_off_schedule_path(date: '2026-10-02', calendar_period: '2026-10-01', role: 'driver', group: 'E', page: 2)
    assert_select '.time-off-calendar tbody tr', 6
    assert_select '.time-off-calendar-pagination', text: /13–18 de 18 colaboradores/
    assert_select '.time-off-calendar-actions span', text: '2 / 2'
    assert_select '.time-off-calendar-actions button[disabled="disabled"]', text: 'Próxima'
    assert_select '.time-off-period-picker input[name="page"][value="2"]', 1
    second_ids = css_select('.time-off-calendar tbody th strong').map(&:text)
    assert_empty first_ids & second_ids
    %w[2026-10-08 month].each do |period|
      get time_off_schedule_path(date: '2026-10-02', calendar_period: period, role: 'driver', group: 'E', page: 2)
      assert_equal second_ids, css_select('.time-off-calendar tbody th strong').map(&:text)
      assert_select '.time-off-calendar-actions span', text: '2 / 2'
    end
    get time_off_schedule_path(date: '2026-10-02', role: 'driver', group: 'E', per_page: 30, page: 999)
    assert_select '.time-off-calendar tbody tr', 6
    assert_select '.time-off-calendar-actions span', text: '2 / 2'
    get time_off_schedule_path(date: '2026-10-02', role: 'helper', group: 'E', page: -2, per_page: 0)
    assert_select '.time-off-calendar tbody tr', 1
    assert_select '.time-off-calendar-pagination', text: /1–1 de 1 colaboradores/
    assert_select '.time-off-calendar-actions button[disabled="disabled"]', 2
    assert_select 'select[name="per_page"]', 0
    get time_off_schedule_path(tab: 'day', date: '2026-10-02', group: 'E', page: 2)
    assert_select '.time-off-person', 19
  end

  test 'periods respect month lengths and keep the monthly roster when switching periods' do
    next_member = TimeOff::AssignGroup.call(schedule: @schedule, person: drivers(:one), group_code: 'A', starts_on: Date.new(2026, 11, 1), user: users(:one))
    TimeOff::UpdateVacation.create(schedule: @schedule, membership_id: next_member.id, starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 3), reason: 'Férias futuras', user: users(:one))
    get time_off_schedule_path(date: '2026-10-30', month: '2026-10', calendar_period: '2026-10-29')
    assert_response :success
    assert_select '.time-off-calendar tbody tr', 1
    assert_select '.time-off-cell--vacation', 0
    get time_off_schedule_path(month: '2026-11', calendar_period: '2026-10-29', date: '2026-10-30')
    assert_select '.time-off-day-link', 7
    assert_select '.time-off-period-picker button[aria-pressed="true"][value="2026-11-01"]', 1
    assert_select '.time-off-calendar tbody tr', 1
    assert_select '.time-off-cell--vacation', 3
    get time_off_schedule_path(month: '2027-02', calendar_period: '2027-02-22')
    assert_equal ['01–07', '08–14', '15–21', '22–28', 'Mês inteiro'], css_select('.time-off-period-picker button').map(&:text)
    assert_select '.time-off-day-link', 7
    get time_off_schedule_path(month: '2028-02', calendar_period: '2028-02-29')
    assert_select '.time-off-period-picker button', text: '29–29', count: 1
    assert_select '.time-off-day-link', 1
    assert_select '.time-off-day-link strong', text: '29'
    drivers(:one).retire!
    get time_off_schedule_path(date: '2026-10-02')
    assert_select '.time-off-calendar-pagination', text: /0–0 de 0 colaboradores/
    assert_select '.time-off-calendar-actions button[disabled="disabled"]', 2
    get time_off_schedule_path(calendar_period: 'invalid')
    assert_redirected_to time_off_schedule_path
  end

  test 'valid JSON adjustment persists and conflicting adjustment returns 409' do
    attributes = { membership_id: @member.id, date: '2026-10-02', status: 'unavailable', reason: 'Atestado', expected_revision: -1 }
    assert_difference('TimeOffOverride.count') do
      patch update_day_time_off_schedule_path, params: { change: attributes }, as: :json
    end
    assert_response :success
    patch update_day_time_off_schedule_path, params: { change: attributes.merge(status: 'working') }, as: :json
    assert_response :conflict
    get time_off_schedule_path(tab: 'day', date: '2026-10-02')
    assert_select '.time-off-column--unavailable .time-off-person', 1
    assert_select '.time-off-person-reason', text: /Atestado/
    assert_select '.time-off-history', 0
    get time_off_schedule_path(tab: 'history', date: '2026-10-02')
    assert_select '.time-off-history li', 1
    assert_select '.time-off-board', 0
    get time_off_schedule_path(tab: 'groups', date: '2026-10-02')
    assert_select '.time-off-membership-form', 1
    assert_select '.time-off-calendar', 1
    assert_select '#time-off-settings', 1
    assert_select '.time-off-board', 0
  end

  test 'ordinary users can consult but cannot edit or assign groups' do
    users(:one).update!(role: :user, sector: :fleet)
    get time_off_schedule_path(tab: 'day', date: '2026-10-02')
    assert_response :success
    assert_select 'dialog', 0
    patch update_day_time_off_schedule_path, params: { change: { membership_id: @member.id } }, as: :json
    assert_response :forbidden
    post assign_group_time_off_schedule_path, params: { membership: { person: "driver:#{drivers(:two).id}", group_code: 'A', starts_on: '2026-10-01' } }
    assert_response :forbidden
  end

  test 'anonymous access requires authentication and invalid dates are handled' do
    get time_off_schedule_path(date: 'invalid')
    assert_redirected_to time_off_schedule_path
    sign_out users(:one)
    get time_off_schedule_path
    assert_redirected_to new_user_session_path
  end

  test 'coverage has moved to the independent DU PCD and its old writers are retired' do
    get time_off_schedule_path(tab: 'coverage', date: '2026-10-02')
    assert_redirected_to pcd_path(date: '2026-10-02')
    assert_no_difference(['TimeOffDailyPlan.count', 'TimeOffChange.count']) do
      patch update_coverage_time_off_schedule_path, params: { board: { date: '2026-10-02' } }, as: :json
      assert_response :gone
      post preview_routing_time_off_schedule_path, params: { date: '2026-10-02' }, as: :json
      assert_response :gone
    end
    users(:one).update!(role: :user, sector: :fleet)
    patch update_coverage_time_off_schedule_path, params: { board: {} }, as: :json
    assert_response :forbidden
  end

  test 'vacations are registered and cancelled with editor access and visible throughout the period' do
    assert_difference(['TimeOffVacation.count', 'TimeOffChange.count'], 1) do
      post create_vacation_time_off_schedule_path(tab: 'day', date: '2026-10-02'), params: { vacation: { membership_id: @member.id, starts_on: '2026-10-02', ends_on: '2026-10-10', reason: 'Férias programadas' } }
    end
    assert_redirected_to time_off_schedule_path(tab: 'day', date: '2026-10-02', settings: 1)
    get time_off_schedule_path(tab: 'day', date: '2026-10-02')
    assert_select '.time-off-column--unavailable .time-off-person[data-movable="false"]', 1
    assert_select '.time-off-vacation-badge', text: /Férias/, count: 1
    assert_select '.time-off-person button', 0
    get time_off_schedule_path(date: '2026-10-02', calendar_period: 'month')
    assert_select '.time-off-cell--vacation', 9
    vacation = @schedule.time_off_vacations.last
    assert_difference('TimeOffChange.count', 1) do
      patch cancel_vacation_time_off_schedule_path(date: '2026-10-02'), params: { vacation: { id: vacation.id, reason: 'Período reagendado' } }
    end
    assert vacation.reload.cancelled_at
    users(:one).update!(role: :user, sector: :fleet)
    post create_vacation_time_off_schedule_path, params: { vacation: { membership_id: @member.id } }
    assert_response :forbidden
    patch cancel_vacation_time_off_schedule_path, params: { vacation: { id: vacation.id } }
    assert_response :forbidden
    get time_off_schedule_path(date: '2026-10-02')
    assert_select '#time-off-settings', 0
  end

  test 'retired drivers and helpers disappear from lists and selectors while their history remains' do
    helper = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'A', starts_on: @schedule.starts_on)
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @member.id, date: Date.new(2026, 10, 2), status: 'working', reason: 'Convocação anterior', expected_revision: -1, user: users(:one))
    TimeOff::UpdateVacation.create(schedule: @schedule, membership_id: helper.id, starts_on: Date.new(2026, 10, 2), ends_on: Date.new(2026, 10, 5), reason: 'Férias anteriores', user: users(:one))
    drivers(:one).retire!
    ajudantes(:one).retire!
    FleetDimensioning.create!(label: 'Outubro', start_date: '2026-10-01', end_date: '2026-10-31', route_quantity: 18)
    %w[calendar day extras].each do |tab|
      get time_off_schedule_path(tab: tab, date: '2026-10-02')
      assert_response :success
      assert_select '.time-off-calendar tbody tr th', 0
      assert_select '.time-off-person, .time-off-chip', 0
      assert_select '.time-off-vacation-period', 0
      assert_select 'select[name="vacation[membership_id]"] option[value=?]', @member.id.to_s, count: 0
      assert_select 'select[name="vacation[membership_id]"] option[value=?]', helper.id.to_s, count: 0
      assert_select 'select[name="membership[person]"] option[value=?]', "driver:#{drivers(:one).id}", count: 0
      assert_select 'select[name="membership[person]"] option[value=?]', "helper:#{ajudantes(:one).id}", count: 0
    end
    get time_off_schedule_path(tab: 'history', date: '2026-10-02')
    assert_select '.time-off-history li', 2
    assert_equal 2, @schedule.time_off_memberships.count
    assert_equal 1, @schedule.time_off_vacations.count
    assert_equal 1, @member.time_off_overrides.count
  end

  test 'inactive RH employee is excluded even when the operational record is active' do
    employee = Employee.create!(nome: 'Desligado', matricula: 'time-off-inactive-rh', active: false)
    drivers(:one).update!(employee: employee)
    assert drivers(:one).active?
    get time_off_schedule_path(date: '2026-10-02')
    assert_response :success
    assert_select '.time-off-calendar tbody tr th', 0
    assert_select 'select[name="membership[person]"] option[value=?]', "driver:#{drivers(:one).id}", count: 0
    patch update_day_time_off_schedule_path, params: { change: { membership_id: @member.id, date: '2026-10-02', status: 'working', reason: 'Tentativa em página antiga', expected_revision: -1 } }, as: :json
    assert_response :unprocessable_entity
    assert_match 'inativo', response.parsed_body['error']
  end

  test 'monthly extras report counts current call ups instead of audit entries' do
    2.times do |i|
      TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @member.id, date: Date.new(2026, 10, 2), status: 'working', reason: 'Convocação', expected_revision: i - 1, user: users(:one))
    end
    get time_off_schedule_path(tab: 'extras', date: '2026-10-02')
    assert_response :success
    assert_select '#time-off-extras .time-off-count', text: '1 extra no mês'
    assert_select '.time-off-extras-table tbody tr', 1
    assert_select '.time-off-extras-table td strong', text: '1'
    assert_select '.time-off-extras-table a', text: '02/10'
  end

end
