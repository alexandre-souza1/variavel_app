require 'test_helper'

class TimeOffGroupSuggestionsTest < ActionDispatch::IntegrationTest
  setup do
    @schedule = TimeOffSchedule.create!(name: 'Sugestões de grupo', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @reserves = [1, 2].map do |number|
      Employees::Registry.create!(attributes: { nome: "RESERVA #{number}", matricula: "SUGGESTION-#{number}" },
        role: { sector: 'du', cargo: 'ajudante', promax: "SUGGESTION-#{number}", starts_on: '2026-10-01', reason: 'Cadastro' }, user: users(:one))
    end
    @context = { date: '2026-10-09', tab: 'calendar', role: 'helper', group: 'E', calendar_period: 'month', name: 'Teste', per_page: '24' }
  end

  test 'individual ignore buttons persist both reserve dismissals without changing their registrations or memberships' do
    @reserves.each do |person|
      get time_off_schedule_path(@context)
      assert_response :success
      assert_select ".time-off-active-suggestions li[data-person-key='employee:#{person.id}'] button[aria-label=?]", "Ignorar sugestão de #{person.nome}"
      assert_no_difference(['TimeOffMembership.count', 'TimeOffChange.count']) do
        patch ignore_suggestion_time_off_schedule_path(@context), params: { person: "employee:#{person.id}" }
        assert_redirected_to time_off_schedule_path(@context)
      end
      assert person.reload.active?
      assert person.eligible_for?(:time_off, date: Date.new(2026, 10, 9))
      assert Pcd::Board.new(date: Date.new(2026, 10, 9)).member("employee:#{person.id}")
    end
    assert_equal @reserves.map { |person| "employee:#{person.id}" }, @schedule.reload.ignored_group_suggestions
    get time_off_schedule_path(date: '2026-10-10')
    @reserves.each do |person|
      assert_select ".time-off-active-suggestions li[data-person-key='employee:#{person.id}']", count: 0
      assert_select ".time-off-ignored-suggestions li[data-person-key='employee:#{person.id}'] strong", text: person.nome
      assert_includes TimeOff::GroupRoster.new(schedule: @schedule, date: Date.new(2026, 10, 10)).people, person
    end
    patch ignore_suggestion_time_off_schedule_path(@context), params: { person: "employee:#{@reserves.first.id}" }
    assert_equal 2, @schedule.reload.ignored_group_suggestions.size
  end

  test 'ignored suggestions are shared by editors and can be restored individually' do
    @schedule.update!(ignored_group_suggestions: @reserves.map { |person| "employee:#{person.id}" })
    users(:one).update!(role: :user, sector: :du)
    get time_off_schedule_path(@context)
    assert_select '.time-off-ignored-suggestions summary strong', text: 'Sugestões ignoradas (2)'
    person = @reserves.first
    patch restore_suggestion_time_off_schedule_path(@context), params: { person: "employee:#{person.id}" }
    assert_redirected_to time_off_schedule_path(@context)
    follow_redirect!
    assert_select ".time-off-active-suggestions li[data-person-key='employee:#{person.id}'] strong", text: person.nome
    assert_select ".time-off-ignored-suggestions li[data-person-key='employee:#{@reserves.last.id}'] strong", text: @reserves.last.nome
  end

  test 'viewers cannot ignore or restore suggestions' do
    users(:one).update!(role: :user, sector: :fleet)
    get time_off_schedule_path(@context)
    assert_response :success
    assert_select '.time-off-suggestion-actions', count: 0
    [ignore_suggestion_time_off_schedule_path, restore_suggestion_time_off_schedule_path].each do |path|
      patch path, params: @context.merge(person: "employee:#{@reserves.first.id}")
      assert_response :forbidden
    end
    assert_empty @schedule.reload.ignored_group_suggestions
  end

  test 'invalid identities and AZ employees cannot be ignored as DU suggestions' do
    az = Employees::Registry.create!(attributes: { nome: 'Pessoa AZ', matricula: 'SUGGESTION-AZ' },
      role: { sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-10-01', reason: 'Cadastro' }, user: users(:one))
    ['employee:999999999', "employee:#{az.id}", 'other:1'].each do |key|
      patch ignore_suggestion_time_off_schedule_path(@context), params: { person: key }
      assert_redirected_to time_off_schedule_path(@context)
      assert flash[:alert].present?
    end
    assert_empty @schedule.reload.ignored_group_suggestions
  end

  test 'ignoring a suggestion still permits assigning the person a group' do
    person = @reserves.first
    @schedule.update!(ignored_group_suggestions: ["employee:#{person.id}"])
    post assign_group_time_off_schedule_path(@context.merge(origin: 'unassigned')), params: {
      membership: { person: "employee:#{person.id}", group_code: 'A', starts_on: '2026-10-09' }
    }
    assert_redirected_to time_off_schedule_path(@context)
    assert_equal 'A', @schedule.time_off_memberships.find_by!(employee_id: person.id).group_code
    get time_off_schedule_path(@context)
    assert_select ".time-off-ignored-suggestions li[data-person-key='employee:#{person.id}']", count: 0
  end

  test 'legacy helpers without central identities also support ignoring and restoring suggestions' do
    Ajudante.insert_all!([{ nome: 'Reserva legada', matricula: 'LEGACY-SUGGESTION', promax: 'LEGACY-SUGGESTION',
      created_at: Time.current, updated_at: Time.current }])
    person = Ajudante.find_by!(matricula: 'LEGACY-SUGGESTION')
    key = "helper:#{person.id}"
    patch ignore_suggestion_time_off_schedule_path(@context), params: { person: key }
    assert_includes @schedule.reload.ignored_group_suggestions, key
    get time_off_schedule_path(@context)
    assert_select ".time-off-ignored-suggestions li[data-person-key='#{key}'] strong", text: person.nome
    patch restore_suggestion_time_off_schedule_path(@context), params: { person: key }
    assert_not_includes @schedule.reload.ignored_group_suggestions, key
  end
end
