require "test_helper"

class ActionPlanDashboardsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @plan = @user.action_plans.create!(name: "Plano do dashboard")
    @bucket = @plan.buckets.find_by!(name: "A Fazer")
    @open = create_task("Aberta sem prazo")
    @late = create_task("Aberta atrasada", due_at: 2.days.ago)
    @done = create_task("Concluída com prazo passado", completed: true, due_at: 3.days.ago)
    @open.users << @user
    @open.users << users(:two)
    @other_plan = @user.action_plans.create!(name: "Outro plano")
    Task.create!(title: "Tarefa de outro plano", bucket: @other_plan.buckets.first, creator: @user)
  end

  test "dashboard scopes totals and clickable charts to the plan without duplicate assignments" do
    get action_plan_path(@plan, view: "dashboard")
    assert_response :success
    assert_select ".action-plan-view-switch__link.active", text: /Dashboard/
    assert_select ".plan-dashboard__metric", text: /3Total de tarefas/
    assert_select ".plan-dashboard__metric", text: /1Atrasadas/
    assert_select ".plan-dashboard__metric", text: /2Sem responsável/
    assert_select ".plan-dashboard__task", count: 3
    assert_select ".plan-dashboard__task", text: /Tarefa de outro plano/, count: 0
    assert_select ".plan-dashboard__bar-segment[href*='status=overdue']"
  end

  test "status and assignment filters only affect the task list" do
    get action_plan_path(@plan, view: "dashboard", status: "overdue")
    assert_response :success
    assert_select ".plan-dashboard__task", count: 1, text: /Aberta atrasada/
    assert_select ".plan-dashboard__metric", text: /3Total de tarefas/
    get action_plan_path(@plan, view: "dashboard", member_id: @user.id, bucket_id: @bucket.id)
    assert_select ".plan-dashboard__task", count: 1, text: /Aberta sem prazo/
    get action_plan_path(@plan, view: "dashboard", member_id: "unassigned")
    assert_select ".plan-dashboard__task", count: 2
    get action_plan_path(@plan, view: "dashboard", bucket_id: @other_plan.buckets.first.id)
    assert_select ".plan-dashboard__task", count: 0
  end

  test "source filter separates GEROT tasks and preserves their origin" do
    template = Routines::PlanTemplateBuilder.call(action_plan: @plan, attributes: { name: "Modelo" })
    category = template.routine_categories.find_by!(bucket: @bucket)
    category.routine_indicators.create!(name: "Indicador", position: 0, calculation_type: :ranged, value_type: :decimal, goal_direction: :less_or_equal)
    routine = Routines::Generator.call(template: template, action_plan: @plan, created_by: @user,
      period_start: Date.current.beginning_of_month, period_end: Date.current.end_of_month)
    generated = create_task("Ação do GEROT", routine_value: routine.routine_values.first)
    get action_plan_path(@plan, view: "dashboard", source: "gerot")
    assert_response :success
    assert_select ".plan-dashboard__task", count: 1, text: /Ação do GEROT/
    assert_select ".plan-dashboard__origin", text: /#{Regexp.escape(routine.title)}/
    assert_select ".plan-dashboard__metric", text: /1Total de tarefas/
    get action_plan_path(@plan, view: "dashboard", source: "manual")
    assert_select ".plan-dashboard__task", count: 3
    assert_select "a.plan-dashboard__task[href=?]", action_plan_path(@plan, task_id: generated.id), count: 0
  end

  test "mechanical users see only assigned tasks in every chart and list" do
    member = users(:two)
    member.update!(role: :mechanical)
    sign_in member
    get action_plan_path(@plan, view: "dashboard")
    assert_response :success
    assert_select ".plan-dashboard__metric", text: /1Total de tarefas/
    assert_select ".plan-dashboard__task", count: 1, text: /Aberta sem prazo/
    assert_select ".plan-dashboard__legend-item", text: /Atrasadas0/
  end

  test "inaccessible plans do not expose a dashboard" do
    @other_plan.update!(user: users(:two), sector: :warehouse, public: false)
    @user.update!(role: :user, sector: :fleet)
    @other_plan.buckets.first.tasks.update_all(creator_id: users(:two).id)
    sign_in @user
    get action_plan_path(@other_plan, view: "dashboard")
    assert_response :not_found
  end

  test "empty plans and invalid source show a usable zero state" do
    empty = @user.action_plans.create!(name: "Vazio")
    get action_plan_path(empty, view: "dashboard", source: "unknown", page: -1)
    assert_response :success
    assert_select ".plan-dashboard__metric", text: /0Total de tarefas/
    assert_select ".plan-dashboard__donut.is-empty"
    assert_select ".plan-dashboard__empty", text: /Nenhuma tarefa/
    assert_select ".plan-dashboard__source.is-active", text: "Todas"
  end

  test "legacy completion values and overdue completed tasks are counted consistently" do
    @open.update_column(:completed, nil)
    get action_plan_path(@plan, view: "dashboard", status: "open")
    assert_response :success
    assert_select ".plan-dashboard__legend-item", text: /Abertas no prazo1/
    assert_select ".plan-dashboard__legend-item", text: /Atrasadas1/
    assert_select ".plan-dashboard__legend-item", text: /Concluídas1/
    assert_select ".plan-dashboard__task", count: 1, text: /Aberta sem prazo/
  end

  test "pagination preserves filters and bounds invalid pages" do
    10.times { |i| create_task("Tarefa #{i}") }
    get action_plan_path(@plan, view: "dashboard", source: "manual", status: "open")
    assert_response :success
    assert_select ".plan-dashboard__task", count: 10
    assert_select ".plan-dashboard__pagination a[href*='page=2'][href*='source=manual'][href*='status=open']"
    get action_plan_path(@plan, view: "dashboard", source: "manual", status: "open", page: 999)
    assert_select ".plan-dashboard__task", count: 1
  end

  private

  def create_task(title, **attributes)
    Task.create!(title: title, bucket: @bucket, creator: @user, **attributes)
  end
end
