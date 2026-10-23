require "test_helper"

class ChecklistTrackingSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @task = tasks(:one)
    @plan = @task.bucket.action_plan
    @person = Employee.create!(nome: "Motorista Configurado", matricula: "CONFIG-01")
    @person.change_role!({ cargo: "motorista", sector: "du", promax: "CONFIG-01", starts_on: "2026-01-01", reason: "Admissão" }, user: @user)
    @record = @task.checklist_occurrences.create!(employee: @person, recorded_by: @user, occurred_on: "2026-03-14", checklist_kind: "saida")
  end

  test "only admins and fleet supervisors can view or change shared source visibility" do
    [[:admin, :hr, true], [:supervisor, :fleet, true], [:supervisor, :du, false],
      [:supervisor, :warehouse, false], [:user, :fleet, false], [:user, :hr, false], [:mechanical, :fleet, false]].each do |role, sector, allowed|
      @user.update!(role: role, sector: sector)
      sign_in @user
      get edit_checklist_tracking_setting_path
      assert_response allowed ? :success : :forbidden
      patch checklist_tracking_setting_path, params: { checklist_tracking_setting: { plan_ids: [@plan.id] } }
      assert_response allowed ? :see_other : :forbidden
      get checklist_occurrences_path
      if role == :mechanical
        assert_response :forbidden
      else
        assert_select "a[href=?]", edit_checklist_tracking_setting_path, count: allowed ? 1 : 0
        assert_select "select[name=action_plan_id]", count: 0
      end
    end
    sign_out @user
    get edit_checklist_tracking_setting_path
    assert_redirected_to new_user_session_path
  end

  test "shared visibility governs totals modal history review and batch without deleting source evidence" do
    @task.update!(title: "Aplicar matriz ao motorista Motorista Configurado por não realização do Checklist de Saída no dia 14/03/2026")
    candidate = @plan.buckets.first.tasks.create!(title: @task.title.sub('14/03', '15/03'), creator: @user)
    patch checklist_tracking_setting_path, params: { checklist_tracking_setting: { plan_ids: [''] } }
    assert_redirected_to checklist_occurrences_path
    assert_not @plan.reload.checklist_tracking_visible?
    @user.update!(role: :user, sector: :du)
    sign_in @user
    get checklist_occurrences_path(year: 2026, action_plan_id: @plan.id)
    assert_select ".checklist-tracking__ranking tr[data-occurrence-count='0']", text: /Motorista Configurado/
    get checklist_occurrences_path(year: 2026, display: 'history')
    assert_select ".checklist-tracking__event", count: 0
    get details_checklist_occurrences_path(year: 2026, employee_id: @person.id)
    assert_select ".checklist-tracking__modal-event", count: 0
    get checklist_occurrences_path(year: 2026, display: 'review')
    assert_select ".checklist-tracking__candidate", count: 0
    assert_no_difference('ChecklistOccurrence.count') { post identify_checklist_occurrences_path, params: { year: 2026, action_plan_id: @plan.id } }
    patch exclude_checklist_occurrence_path(@record), params: { exclusion: { reason: 'turned_map' } }, as: :json
    assert_response :not_found
    assert_nil @record.reload.cancelled_at
    assert Task.exists?(candidate.id)
    @user.update!(role: :supervisor, sector: :fleet)
    sign_in @user
    patch checklist_tracking_setting_path, params: { checklist_tracking_setting: { plan_ids: [@plan.id] } }
    @user.update!(role: :user, sector: :du)
    sign_in @user
    get checklist_occurrences_path(year: 2026)
    assert_select ".checklist-tracking__ranking .checklist-tracking__total", text: '1'
    get checklist_occurrences_path(year: 2026, display: 'review')
    assert_select ".checklist-tracking__candidate strong", text: candidate.title
  end

  test "fleet supervisors cannot enumerate or change private plans outside their access" do
    owner = users(:two)
    owner.update!(sector: :warehouse)
    private_plan = owner.action_plans.create!(name: 'Origem privada AZ', public: false, sector: :warehouse)
    @user.update!(role: :supervisor, sector: :fleet)
    sign_in @user
    get edit_checklist_tracking_setting_path
    assert_not_includes response.body, private_plan.name
    patch checklist_tracking_setting_path, params: { checklist_tracking_setting: { plan_ids: [@plan.id, private_plan.id] } }
    assert_redirected_to edit_checklist_tracking_setting_path
    assert private_plan.reload.checklist_tracking_visible?
    patch checklist_tracking_setting_path, params: { checklist_tracking_setting: { plan_ids: [''] } }
    assert_not @plan.reload.checklist_tracking_visible?
    assert private_plan.reload.checklist_tracking_visible?
  end
end
