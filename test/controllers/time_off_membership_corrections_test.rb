require 'test_helper'

class TimeOffMembershipCorrectionsTest < ActionDispatch::IntegrationTest
  setup do
    @schedule = TimeOffSchedule.create!(name: 'Piloto', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @member = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'A', starts_on: '2026-10-08')
  end

  test 'configuration offers future memberships independent of calendar filters' do
    get time_off_schedule_path(date: '2026-10-07', role: 'driver', group: 'F', name: 'Outro nome', settings: 1, correction: 1, membership_id: @member.id)
    assert_response :success
    assert_select '.time-off-membership-correction[open]', 1
    assert_select '#correction-membership option[selected][value=?][data-starts-on="2026-10-08"]', @member.id.to_s, count: 1
    assert_select '.time-off-correction-form input[name="_method"][value="patch"]', 1
    assert_select '.time-off-correction-form textarea[required][maxlength="500"]', 1
    assert_select '.group-assignment-form a[href*="correction=1"]'
  end

  test 'editors correct a future start and the calendar day and audit reflect the corrected date' do
    context = { date: '2026-10-07', tab: 'calendar', group: 'A', role: 'helper', calendar_period: '2026-10-08', per_page: 24 }
    assert_no_difference('TimeOffMembership.count') do
      assert_difference('TimeOffChange.count', 1) do
        patch revise_membership_time_off_schedule_path(context), params: { membership: attributes }
      end
    end
    assert_redirected_to time_off_schedule_path(context.merge(settings: 1, correction: 1, membership_id: @member.id))
    assert_equal Date.new(2026, 10, 14), @member.reload.starts_on
    get time_off_schedule_path(date: '2026-10-13', tab: 'day')
    assert_select '.time-off-person', 0
    get time_off_schedule_path(date: '2026-10-14', tab: 'day')
    assert_select '.time-off-person', 1
    get time_off_schedule_path(date: '2026-10-14', tab: 'history')
    assert_response :success
    assert_select '.time-off-history', text: /Vigência corrigida: Grupo A, início 08\/10\/2026 → Grupo A, início 14\/10\/2026/
    assert_select '.time-off-history p', text: 'Começa após o dia 13'
  end

  test 'invalid data and stale pages leave the period unchanged and return to correction settings' do
    [{ starts_on: 'invalid' }, { reason: '' }, { expected_updated_at: 'stale' }, { group_code: 'invalid' }].each do |invalid|
      assert_no_difference('TimeOffChange.count') do
        patch revise_membership_time_off_schedule_path(date: '2026-10-07'), params: { membership: attributes.merge(invalid) }
      end
      assert_redirected_to time_off_schedule_path(tab: 'calendar', date: '2026-10-07', settings: 1, correction: 1, membership_id: @member.id)
      assert flash[:alert].present?
      assert_equal Date.new(2026, 10, 8), @member.reload.starts_on
    end
  end

  test 'archived adjustments remain readable in the correction history' do
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: @member.id, date: Date.new(2026, 10, 9),
      status: 'unavailable', reason: 'Atestado lançado antes da correção', expected_revision: -1, user: users(:one))
    patch revise_membership_time_off_schedule_path(date: '2026-10-07'), params: { membership: attributes }
    get time_off_schedule_path(date: '2026-10-14', tab: 'history')
    assert_response :success
    assert_select '.time-off-history', text: /1 ajuste arquivado/
    assert_select '.time-off-history details p', text: /09\/10\/2026 · Indisponível · Atestado lançado antes da correção/
  end

  test 'ordinary users and anonymous visitors cannot correct memberships' do
    users(:one).update!(role: :user, sector: :fleet)
    assert_no_difference('TimeOffChange.count') do
      patch revise_membership_time_off_schedule_path, params: { membership: attributes }
      assert_response :forbidden
    end
    get time_off_schedule_path(date: '2026-10-07')
    assert_select '.time-off-correction-form', 0
    sign_out users(:one)
    patch revise_membership_time_off_schedule_path, params: { membership: attributes }
    assert_redirected_to new_user_session_path
  end

  test 'a membership from another schedule cannot be corrected' do
    other = TimeOffSchedule.create!(name: 'Outra escala', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28')
    foreign = other.time_off_memberships.create!(ajudante: ajudantes(:two), group_code: 'A', starts_on: '2026-10-08')
    assert_no_difference('TimeOffChange.count') do
      patch revise_membership_time_off_schedule_path, params: { membership: attributes.merge(id: foreign.id, expected_updated_at: foreign.updated_at.iso8601(6)) }
      assert_response :not_found
    end
  end

  private

  def attributes
    { id: @member.id, starts_on: '2026-10-14', group_code: 'A', reason: 'Começa após o dia 13', expected_updated_at: @member.updated_at.iso8601(6) }
  end
end
