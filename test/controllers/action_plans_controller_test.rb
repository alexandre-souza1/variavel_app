require "test_helper"

class ActionPlansControllerTest < ActionDispatch::IntegrationTest
  test "lists active plans on the dashboard and archived plans on their own page" do
    active_plan = users(:one).action_plans.create!(name: "Plano ativo")
    archived_plan = users(:one).action_plans.create!(name: "Plano arquivado", archived_at: Time.current)

    get action_plans_path
    assert_response :success
    assert_select ".plan-name", text: active_plan.name, count: 2
    assert_select ".plan-name", text: archived_plan.name, count: 0
    assert_select ".header-actions a[href=?]", archived_action_plans_path, text: /Arquivados/, count: 1
    assert_select "nav[aria-label='Filtrar planos']", count: 0
    assert_select "a", text: "Ativos", count: 0
    assert_select ".header-actions a", text: /Acompanhamento de Checklist/, count: 0
    assert_select "form[action=?]", archive_action_plan_path(active_plan), count: 2

    get archived_action_plans_path
    assert_response :success
    assert_select ".plan-name", text: archived_plan.name, count: 1
    assert_select "h1", text: /Planos arquivados/
    assert_select ".kpi-card, .calendar-body, #plansOffcanvas", count: 0
    assert_select ".header-actions a[href=?]", action_plans_path, text: /Meu Painel/
    assert_select ".plan-name", text: active_plan.name, count: 0
    assert_select "form[action=?]", unarchive_action_plan_path(archived_plan), count: 1
  end

  test "legacy archive links redirect to the dedicated page preserving filters" do
    get action_plans_path(status: "archived", query: "Histórico", show_hidden: "1")

    assert_redirected_to archived_action_plans_path(query: "Histórico", show_hidden: "1")
    follow_redirect!
    assert_response :success
    assert_select "h1", text: /Planos arquivados/
    assert_select "form[action=?] input[name=query][value=?]", archived_action_plans_path, "Histórico"
  end

  test "empty archive offers a return to the dashboard and requires authentication" do
    get archived_action_plans_path
    assert_response :success
    assert_select ".empty-state-compact", text: /Nenhum plano arquivado encontrado/
    assert_select ".header-actions a[href=?]", action_plans_path

    sign_out users(:one)
    get archived_action_plans_path
    assert_redirected_to new_user_session_path
  end

  test "archive filters preserve search and personal hiding preferences" do
    plan = users(:one).action_plans.create!(name: "Histórico anual", archived_at: Time.current)
    users(:one).hidden_action_plans.create!(action_plan: plan)

    get archived_action_plans_path(query: "Histórico")
    assert_response :success
    assert_select ".plan-name", text: plan.name, count: 0
    assert_select "a[aria-label='Ver planos ocultos']" do |links|
      links.each do |link|
        query = Rack::Utils.parse_nested_query(URI.parse(link["href"]).query)
        assert_equal archived_action_plans_path, URI.parse(link["href"]).path
        assert_nil query["status"]
        assert_equal "Histórico", query["query"]
        assert_equal "1", query["show_hidden"]
      end
    end

    get archived_action_plans_path(query: "Histórico", show_hidden: "1")
    assert_select ".plan-name", text: plan.name, count: 1

    get archived_action_plans_path(query: "Outro", show_hidden: "1")
    assert_select ".plan-name", text: plan.name, count: 0

    get action_plans_path(show_hidden: "1")
    assert_select ".plan-name", text: plan.name, count: 0
  end

  test "owners can archive and restore their plans" do
    users(:one).update!(role: :user)
    plan = users(:one).action_plans.create!(name: "Meu plano")
    task = plan.buckets.first.tasks.create!(title: "Pendência preservada", creator: users(:one))
    task.users << users(:two)

    patch archive_action_plan_path(plan)
    assert_redirected_to archived_action_plans_path
    assert plan.reload.archived?

    sign_in users(:two)
    get action_plans_path
    assert_select ".plan-name", text: plan.name, count: 0
    assert_select ".task-item-link[href=?]", action_plan_path(plan, task_id: task.id)
    get archived_action_plans_path
    assert_select ".plan-name", text: plan.name, count: 1

    sign_in users(:one)
    patch unarchive_action_plan_path(plan)
    assert_redirected_to action_plans_path
    assert_not plan.reload.archived?
  end

  test "admins can archive and restore plans owned by other users" do
    plan = users(:two).action_plans.create!(name: "Plano de outro usuário")

    patch archive_action_plan_path(plan)
    assert_redirected_to archived_action_plans_path
    assert plan.reload.archived?

    patch unarchive_action_plan_path(plan)
    assert_redirected_to action_plans_path
    assert_not plan.reload.archived?
  end

  test "users with access cannot archive or restore someone else's plan" do
    users(:one).update!(role: :user)
    plan = users(:two).action_plans.create!(name: "Plano compartilhado", public: true)

    get action_plan_path(plan)
    assert_response :success
    assert_select "form[action=?]", archive_action_plan_path(plan), count: 0

    patch archive_action_plan_path(plan)
    assert_response :not_found
    assert_not plan.reload.archived?

    plan.archive!
    get action_plan_path(plan)
    assert_response :success
    assert_select "form[action=?]", unarchive_action_plan_path(plan), count: 0

    patch unarchive_action_plan_path(plan)
    assert_response :not_found
    assert plan.reload.archived?
  end

  test "archived plans remain accessible only to authorized users" do
    owner = users(:two)
    owner.update!(sector: :du)
    plan = owner.action_plans.create!(name: "Histórico privado", public: false)
    plan.archive!

    get action_plan_path(plan)
    assert_response :success
    assert_select "[role=status]", text: /Este plano foi arquivado/
    assert_select "form[action=?]", unarchive_action_plan_path(plan)

    users(:one).update!(role: :user, sector: :fleet)
    get action_plan_path(plan)
    assert_response :not_found
    get archived_action_plans_path
    assert_response :success
    assert_select ".plan-name", text: plan.name, count: 0
  end

  test "archiving requires authentication" do
    plan = action_plans(:one)
    sign_out users(:one)

    patch archive_action_plan_path(plan)
    assert_redirected_to new_user_session_path
    assert_not plan.reload.archived?

    plan.archive!
    patch unarchive_action_plan_path(plan)
    assert_redirected_to new_user_session_path
    assert plan.reload.archived?
  end

  test "label cloud links to the task search and preserves label management" do
    plan = users(:one).action_plans.create!(name: "Etiquetas")
    label = plan.labels.create!(name: "Manutenção & revisão", color: "#3616b6")
    get action_plan_path(plan, view: "labels")
    assert_response :success
    assert_select ".action-plan-label-cloud__word[href=?]",
      action_plan_path(plan, view: "list", label_query: label.name), text: label.name
    assert_select ".action-plan-label-cloud__delete[aria-label=?]", "Excluir etiqueta #{label.name}"
    get action_plan_path(plan, view: "list", label_query: label.name)
    assert_response :success
    assert_select "input[data-action-plan-filter-target=query][value=?]", label.name
  end

  test "new renders the plan form without the meeting recorder" do
    get new_action_plan_url

    assert_response :success
    assert_select 'form[action=?]', action_plans_path
    assert_select "#meeting-recorder-widget", count: 0
  end

  test "invalid creation renders the form without the meeting recorder" do
    assert_no_difference("ActionPlan.count") do
      post action_plans_url, params: { action_plan: { name: "" } }
    end

    assert_response :success
    assert_select 'form[action=?]', action_plans_path
    assert_select "#meeting-recorder-widget", count: 0
  end

  test "saved plans still display the meeting recorder" do
    action_plan = users(:one).action_plans.create!(name: "Plano de melhoria")

    get action_plan_url(action_plan)

    assert_response :success
    assert_select "#meeting-recorder-widget" do
      assert_select 'form[action=?]', action_plan_meeting_minutes_path(action_plan)
    end
  end
end
