require 'test_helper'

class TimeOffMembershipDeletionsTest < ActionDispatch::IntegrationTest
  setup do
    @schedule = TimeOffSchedule.create!(name: 'Escala', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @member = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'B', starts_on: '2026-10-08')
  end

  test 'editors delete a selected period and history remains available' do
    context = { date: '2026-10-08', group: 'B', role: 'helper', per_page: 24 }
    get time_off_schedule_path(context.merge(settings: 1, correction: 1))
    assert_select '.time-off-correction-form button[formaction*="excluir-vigencia"]', text: 'Excluir vigência'
    assert_difference('TimeOffMembership.active.count', -1) do
      assert_difference('TimeOffChange.count', 1) do
        patch delete_membership_time_off_schedule_path(context), params: { membership: attributes }
      end
    end
    assert_redirected_to time_off_schedule_path(context.merge(tab: 'calendar', settings: 1, correction: 1))
    get time_off_schedule_path(date: '2026-10-08', tab: 'history')
    assert_response :success
    assert_select '.time-off-history', text: /Vigência excluída: Grupo B · 08\/10\/2026 em diante/
    assert_select '.time-off-history p', text: 'Cadastro incorreto'
    get time_off_schedule_path(date: '2026-10-08', settings: 1, correction: 1)
    assert_select '#correction-membership option[value=?]', @member.id.to_s, count: 0
    assert_select '.time-off-calendar tbody tr[data-membership-id=?]', @member.id.to_s, count: 0
    patch delete_membership_time_off_schedule_path, params: { membership: attributes }
    assert_response :not_found
  end

  test 'maintenance repairs retain an audit without impersonating a user' do
    TimeOff::DeleteMembership.call(schedule: @schedule, membership_id: @member.id,
      expected_updated_at: @member.updated_at.iso8601(6), reason: 'Manutenção solicitada pelo responsável', user: nil)
    get time_off_schedule_path(date: '2026-10-08', tab: 'history')
    assert_response :success
    assert_select '.time-off-history small', text: /Manutenção da escala/
    assert_nil @schedule.time_off_changes.last.user_id
  end

  test 'stale or blank requests cannot remove the selected period' do
    [{ reason: '' }, { expected_updated_at: 'stale' }].each do |invalid|
      assert_no_difference('TimeOffChange.count') do
        patch delete_membership_time_off_schedule_path, params: { membership: attributes.merge(invalid) }
      end
      assert flash[:alert].present?
      assert_nil @member.reload.cancelled_at
    end
  end

  test 'foreign memberships and unauthorized visitors cannot delete periods' do
    other = TimeOffSchedule.create!(name: 'Outra escala', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28')
    foreign = other.time_off_memberships.create!(ajudante: ajudantes(:two), group_code: 'A', starts_on: '2026-10-08')
    patch delete_membership_time_off_schedule_path, params: { membership: attributes.merge(id: foreign.id) }
    assert_response :not_found
    users(:one).update!(role: :user, sector: :fleet)
    sign_in users(:one)
    patch delete_membership_time_off_schedule_path, params: { membership: attributes }
    assert_response :forbidden
    sign_out users(:one)
    patch delete_membership_time_off_schedule_path, params: { membership: attributes }
    assert_redirected_to new_user_session_path
    assert_nil @member.reload.cancelled_at
  end

  private

  def attributes
    { id: @member.id, expected_updated_at: @member.updated_at.iso8601(6), reason: 'Cadastro incorreto' }
  end
end
