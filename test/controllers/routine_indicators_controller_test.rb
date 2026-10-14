require "test_helper"

class RoutineIndicatorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @plan = @user.action_plans.create!(name: "Plano de badges", sector: @user.sector)
    @template = Routines::PlanTemplateBuilder.call(action_plan: @plan)
    @category = @template.routine_categories.first
    @indicator = @category.routine_indicators.create!(name: "Conformidade", position: 0)
    @label = @plan.labels.create!(name: "Segurança", color: "#ff6600")
    @second_label = @plan.labels.create!(name: "Frota", color: "#3366ff")
    @routine = Routines::Generator.call(template: @template, action_plan: @plan, created_by: @user,
      period_start: Date.new(2026, 10, 1), period_end: Date.new(2026, 10, 3))
  end

  test "indicator form lists plan badges and saves multiple selections on create and edit" do
    get new_routine_template_routine_category_routine_indicator_path(@template, @category)
    assert_response :success
    assert_select "input[name='routine_indicator[label_ids][]'][value=?]", @label.id.to_s
    assert_select "input[name='routine_indicator[label_ids][]'][value=?]", @second_label.id.to_s

    post routine_template_routine_category_routine_indicators_path(@template, @category), params: {
      routine_indicator: { name: "Checklist", label_ids: ["", @label.id, @second_label.id] }
    }
    assert_response :redirect
    created = @category.routine_indicators.find_by!(name: "Checklist")
    assert_equal [@label.id, @second_label.id].sort, created.label_ids.sort

    patch routine_template_routine_category_routine_indicator_path(@template, @category, created), params: {
      routine_indicator: { label_ids: ["", @second_label.id] }
    }
    assert_equal [@second_label.id], created.reload.label_ids

    get edit_routine_template_routine_category_routine_indicator_path(@template, @category, created)
    assert_select "input[type=checkbox][value=?][checked]", @second_label.id.to_s
    get action_plan_gerot_template_path(@plan)
    assert_select ".routine-indicator-labels .badge", text: "Frota"
  end

  test "routine grid displays badges and allows adding replacing and clearing them" do
    @indicator.update!(labels: [@label])
    get routine_path(@routine)
    assert_response :success
    assert_select ".indicator-row .routine-indicator-labels .badge", text: "Segurança"
    assert_select "button[aria-controls=?]", "routineIndicatorLabelsPopover-#{@routine.id}-#{@indicator.id}"
    assert_select ".routine-indicator-label-popover[popover=manual]"
    assert_select ".routine-indicator-label-modal", count: 0
    assert_select "form[action=?]", routine_indicator_label_path(@routine, @indicator)

    patch routine_indicator_label_path(@routine, @indicator), params: {
      routine_indicator: { name: "Tentativa de renomear", label_ids: ["", @label.id, @second_label.id] }
    }
    assert_redirected_to routine_path(@routine)
    assert_equal [@label.id, @second_label.id].sort, @indicator.reload.label_ids.sort
    assert_equal "Conformidade", @indicator.name

    patch routine_indicator_label_path(@routine, @indicator), params: { routine_indicator: { label_ids: [""] } }
    assert_redirected_to routine_path(@routine)
    assert_empty @indicator.reload.labels
  end

  test "badges of another plan are rejected without replacing existing badges" do
    @indicator.update!(labels: [@label])
    other_plan = @user.action_plans.create!(name: "Outro plano", sector: @user.sector)
    foreign_label = other_plan.labels.create!(name: "Externa", color: "#112233")

    patch routine_template_routine_category_routine_indicator_path(@template, @category, @indicator), params: {
      routine_indicator: { label_ids: [foreign_label.id] }
    }
    assert_response :unprocessable_entity
    assert_equal [@label.id], @indicator.reload.label_ids

    patch routine_indicator_label_path(@routine, @indicator), params: { routine_indicator: { label_ids: [foreign_label.id] } }
    assert_redirected_to routine_path(@routine)
    assert flash[:alert].present?
    assert_equal [@label.id], @indicator.reload.label_ids
  end

  test "turbo changes update only the compact labels and save status" do
    patch routine_indicator_label_path(@routine, @indicator), params: {
      routine_indicator: { label_ids: ["", @label.id, @second_label.id] }
    }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal [@label.id, @second_label.id].sort, @indicator.reload.label_ids.sort
    target = "routine-indicator-labels-#{@routine.id}-#{@indicator.id}"
    assert_select "turbo-stream[action=update][target=?]", target do
      assert_select ".badge", text: "Frota", count: 1
      assert_select ".routine-indicator-label-count", text: "+1"
    end
    assert_select "turbo-stream[action=update][target=?]", "routine-indicator-labels-status-#{@routine.id}-#{@indicator.id}", text: /Salvo/
    assert_select "turbo-stream", count: 2

    patch routine_indicator_label_path(@routine, @indicator), params: { routine_indicator: { label_ids: [""] } }, as: :turbo_stream
    assert_response :success
    assert_empty @indicator.reload.labels
    assert_select "turbo-stream[target=?] .badge", target, count: 0
  end

  test "turbo rejects foreign labels and reports errors inside the picker" do
    @indicator.update!(labels: [@label])
    other_plan = @user.action_plans.create!(name: "Outro plano com etiquetas", sector: @user.sector)
    foreign_label = other_plan.labels.create!(name: "Externa", color: "#112233")

    patch routine_indicator_label_path(@routine, @indicator), params: {
      routine_indicator: { label_ids: [foreign_label.id] }
    }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal [@label.id], @indicator.reload.label_ids
    assert_select "turbo-stream[target=?] .text-danger", "routine-indicator-labels-status-#{@routine.id}-#{@indicator.id}", text: /deve pertencer ao plano/
    assert_select "turbo-stream", count: 1
  end

  test "plan viewers see badges without controls and cannot change them" do
    viewer = User.create!(email: "badge-viewer@example.com", password: "password123", role: :user, sector: @plan.sector)
    @indicator.update!(labels: [@label])
    sign_in viewer

    get routine_path(@routine)
    assert_response :success
    assert_select ".indicator-row .routine-indicator-labels .badge", text: "Segurança"
    assert_select ".routine-indicator-label-trigger", count: 0
    assert_select "form[action=?]", routine_indicator_label_path(@routine, @indicator), count: 0

    patch routine_indicator_label_path(@routine, @indicator), params: { routine_indicator: { label_ids: [""] } }
    assert_response :forbidden
    assert_equal [@label.id], @indicator.reload.label_ids

    patch routine_indicator_label_path(@routine, @indicator), params: { routine_indicator: { label_ids: [""] } }, as: :turbo_stream
    assert_response :forbidden
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[target=?] .text-danger", "routine-indicator-labels-status-#{@routine.id}-#{@indicator.id}", text: /não tem permissão/
    assert_equal [@label.id], @indicator.reload.label_ids
  end

  test "plan owner can change indicator badges" do
    @user.update!(role: :user)
    patch routine_indicator_label_path(@routine, @indicator), params: { routine_indicator: { label_ids: [@label.id] } }
    assert_redirected_to routine_path(@routine)
    assert_equal [@label.id], @indicator.reload.label_ids
  end

  test "routine badge endpoint rejects indicators outside the selected routine" do
    excluded = @category.routine_indicators.create!(name: "Não selecionado", position: 1)
    patch routine_indicator_label_path(@routine, excluded), params: { routine_indicator: { label_ids: [@label.id] } }
    assert_response :not_found
    assert_empty excluded.reload.labels
  end

  test "deleting a plan badge removes indicator assignments" do
    @indicator.update!(labels: [@label, @second_label])
    delete action_plan_label_path(@plan, @label)
    assert_redirected_to action_plan_path(@plan, view: "labels")
    assert_equal [@second_label.id], @indicator.reload.label_ids
    assert_not RoutineIndicatorLabel.exists?(label_id: @label.id)
  end

  test "independent routines have no plan badge controls" do
    routine = routines(:one)
    get routine_path(routine)
    assert_response :success
    assert_select ".routine-indicator-label-trigger", count: 0
    patch routine_indicator_label_path(routine, routine_indicators(:one)), params: { routine_indicator: { label_ids: [@label.id] } }
    assert_response :forbidden
  end
end
