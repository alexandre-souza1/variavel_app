require 'test_helper'

class EmployeeGroupsAndSectorAccessTest < ActionDispatch::IntegrationTest
  setup do
    @du = Employees::Registry.create!(attributes: { nome: 'Pessoa DU para escala', matricula: 'GROUP-DU' },
      role: { sector: 'du', cargo: 'motorista', promax: 'GROUP-DU', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    @az = Employees::Registry.create!(attributes: { nome: 'Pessoa AZ restrita', matricula: 'GROUP-AZ' },
      role: { sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    @schedule = TimeOffSchedule.create!(name: 'Escala de grupos', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
  end

  test 'DU and AZ sectors stay isolated for users supervisors and admins including shared links' do
    %i[user supervisor admin].each do |role|
      { du: [@du, @az, 'du'], warehouse: [@az, @du, 'az'] }.each do |sector, (visible, forbidden, expected)|
        users(:one).update!(role: role, sector: sector)
        get employees_path(employee_sector: expected == 'du' ? 'az' : 'du')
        assert_response :success
        assert_select '.employees-person strong', text: visible.nome
        assert_select '.employees-person strong', text: forbidden.nome, count: 0
        assert_equal [expected], css_select('select[name=employee_sector] option').map { |option| option['value'] }
        get employee_path(forbidden)
        assert_response :forbidden
        get(expected == 'du' ? operator_path(@az.operators.first) : driver_path(@du.drivers.first))
        assert_response :forbidden
        get employee_path(visible)
        assert_response :success
        assert_select '.employees-back[href=?]', employees_path(employee_sector: expected)
        get employees_path
        assert_select '.employees-person strong', text: forbidden.nome, count: 0
      end
    end
  end

  test 'restricted managers cannot create or transfer a person into the other sector' do
    users(:one).update!(role: :supervisor, sector: :du)
    assert_no_difference('Employee.count') do
      post employees_path, params: { employee: { nome: 'Inválido', matricula: 'FORGED-AZ' }, employee_role: { sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-10-01' } }
      assert_response :forbidden
    end
    assert_no_difference('EmployeeRole.count') do
      post change_role_employee_path(@du), params: { employee_role: { sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-10-01', reason: 'Transferência' } }
      assert_response :forbidden
    end
  end

  test 'archive counts do not expose the other sector and future transfers keep current access' do
    @az.retire!(user: users(:one))
    @du.change_role!({ sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-11-01', reason: 'Transferência futura' }, user: users(:one))
    users(:one).update!(sector: :du)
    travel_to Time.zone.local(2026, 10, 7) do
      get employees_path
      assert_select '.employees-person strong', text: @du.nome
      assert_select '.app-page-actions a', text: /Arquivados/, count: 0
      get employees_path(status: 'archived', employee_sector: 'az')
      assert_select '.employees-person strong', text: @az.nome, count: 0
      get employee_path(@du)
      assert_response :success
      assert_select '.employees-timeline h3', text: /AZ/, count: 0
    end
  end

  test 'list keeps filters in edit and save redirects for corporate management' do
    context = { employee_sector: 'az', q: 'Pessoa', turno: '0' }
    get employees_path(context)
    assert_select '.employees-person[href=?]', employee_path(@az, context)
    get employee_path(@az, context)
    assert_select '.employees-back[href=?]', employees_path(context)
    assert_select '.app-page-actions a[href=?]', edit_employee_path(@az, context)
    patch employee_path(@az, context), params: { employee: { nome: 'Pessoa AZ corrigida' }, reason: 'Correção' }
    assert_redirected_to employee_path(@az, context)
    get operator_path(@az.operators.first, employee_sector: 'az')
    assert_redirected_to employee_path(@az, employee_sector: 'az')
  end

  test 'sector navigation does not report request parameters as unpermitted' do
    warnings = []
    subscriber = ->(event) { warnings.concat(event.payload[:keys]) }

    ActiveSupport::Notifications.subscribed(subscriber, 'unpermitted_parameters.action_controller') do
      %w[du az].each do |sector|
        context = { employee_sector: sector, q: 'Pessoa' }
        person = sector == 'du' ? @du : @az
        get employees_path(context)
        assert_response :success
        assert_select '.employees-person[href=?]', employee_path(person, context)
        get employee_path(person, context)
        assert_response :success
        assert_select '.employees-back[href=?]', employees_path(context)
      end

      get operator_path(@az.operators.first, employee_sector: 'az')
      assert_redirected_to employee_path(@az, employee_sector: 'az')
    end

    assert_empty warnings
  end

  test 'group column reuses existing dated groups and leaves unassigned and AZ cells blank' do
    @schedule.time_off_memberships.create!(driver: @du.drivers.first, group_code: 'E', starts_on: '2026-10-01')
    travel_to Time.zone.local(2026, 10, 7) do
      get employees_path
      assert_response :success
      assert_select "td[data-employee-id='#{@du.id}'] .employees-group-value", text: 'E'
      assert_select "td[data-employee-id='#{@du.id}'] form", count: 0
      assert_select "td[data-employee-id='#{@du.id}'] button[aria-controls='group-dialog-employee-#{@du.id}']", count: 1
      assert_select "dialog#group-dialog-employee-#{@du.id} select[name='membership[group_code]'] option[selected]", text: 'Grupo E'
      assert_select "td[data-employee-id='#{@az.id}']", text: ''
      assert_select "td[data-employee-id='#{@az.id}'] form", count: 0
      TimeOffMembership.where(time_off_schedule_id: @schedule.id).delete_all
      get employees_path
      assert_select "td[data-employee-id='#{@du.id}'] .employees-group-value", text: ''
      assert_select "#group_employee_#{@du.id}_code option[selected]", count: 0
    end
  end

  test 'DU users correct groups from list on the same membership with audit and validated dates' do
    original = @schedule.time_off_memberships.create!(driver: @du.drivers.first, group_code: 'E', starts_on: '2026-10-01')
    # Older adapter memberships may not yet have the central employee id.
    original.update_column(:employee_id, nil)
    users(:one).update!(role: :user, sector: :du)
    travel_to Time.zone.local(2026, 10, 7) do
      context = { employee_sector: 'du', q: 'Pessoa' }
      attributes = { id: original.id, group_code: 'A', starts_on: '2026-10-12', reason: 'Em integração', expected_updated_at: original.updated_at.iso8601(6) }
      get employees_path(context)
      assert_select "dialog#group-dialog-employee-#{@du.id} form[action=?]", revise_membership_employee_path(@du, context)
      assert_select "#group_employee_#{@du.id}_start[value='2026-10-01']", 1
      assert_no_difference('TimeOffMembership.count') do
        assert_difference('TimeOffChange.count', 1) do
          patch revise_membership_employee_path(@du, context), params: { membership: attributes }
        end
      end
      assert_redirected_to employees_path(context)
      assert_equal Date.new(2026, 10, 12), original.reload.starts_on
      assert_nil original.ends_on
      assert_equal 'A', original.group_code
      get employees_path(context)
      assert_select "#group_employee_#{@du.id}_membership[value='#{original.id}']", 1
      assert_select "#group_employee_#{@du.id}_start[value='2026-10-12']", 1
      assert_no_difference('TimeOffMembership.count') do
        post assign_group_employee_path(@du, context), params: { membership: attributes.merge(group_code: 'B') }
      end
      assert_match /corrigir o vínculo existente/, flash[:alert]
      patch revise_membership_employee_path(@az), params: { membership: attributes }
      assert_response :forbidden
      post assign_group_employee_path(@az), params: { membership: attributes }
      assert_response :forbidden
    end
  end

  test 'correction cannot access another employee membership and new changes require explicit intent' do
    own = @schedule.time_off_memberships.create!(driver: @du.drivers.first, group_code: 'A', starts_on: '2026-10-01')
    foreign = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'B', starts_on: '2026-10-01')
    attributes = { id: foreign.id, group_code: 'C', starts_on: '2026-10-12', reason: 'Teste', expected_updated_at: foreign.updated_at.iso8601(6) }
    patch revise_membership_employee_path(@du), params: { membership: attributes }
    assert_response :not_found
    sign_in users(:one)
    attributes = { person: "employee:#{@du.id}", group_code: 'B', starts_on: '2026-10-12' }
    assert_no_difference('TimeOffMembership.count') do
      post assign_group_time_off_schedule_path, params: { membership: attributes }
    end
    assert_match /marque a opção correspondente/, flash[:alert]
    assert_difference('TimeOffMembership.count', 1) do
      post assign_group_time_off_schedule_path, params: { membership: attributes.merge(new_change: '1') }
    end
    assert_equal Date.new(2026, 10, 11), own.reload.ends_on
    assert_equal 'B', @schedule.time_off_memberships.for_person(@du).on(Date.new(2026, 10, 12)).sole.group_code
  end

  test 'schedule highlights unassigned DU people independently of filters and allows assignment there' do
    get time_off_schedule_path(date: '2026-10-07', group: 'E', role: 'helper')
    assert_response :success
    assert_select ".time-off-unassigned-list li[data-person-key='employee:#{@du.id}'] strong", text: @du.nome
    assert_select '.time-off-unassigned-list strong', text: @az.nome, count: 0
    context = { date: '2026-10-07', tab: 'calendar', role: 'helper', group: 'E' }
    post assign_group_time_off_schedule_path(context.merge(origin: 'unassigned')), params: { membership: { person: "employee:#{@du.id}", group_code: 'A', starts_on: '2026-10-07' } }
    assert_redirected_to time_off_schedule_path(context)
    get time_off_schedule_path(date: '2026-10-07')
    assert_select '.time-off-unassigned-list strong', text: @du.nome, count: 0
    users(:one).update!(role: :user, sector: :fleet)
    get time_off_schedule_path(date: '2026-10-07')
    assert_select '.time-off-unassigned-list form', count: 0
  end
end
