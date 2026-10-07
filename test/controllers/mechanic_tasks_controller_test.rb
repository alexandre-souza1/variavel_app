require "test_helper"

class MechanicTasksControllerTest < ActionDispatch::IntegrationTest
  test "mecânico vê apenas a própria lista de tarefas" do
    user = users(:one)
    user.update!(role: :mechanical)
    sign_in user

    get mechanic_tasks_path

    assert_response :success
    assert_select "h1", "Minhas tarefas"
    assert_select ".mechanic-task", count: 1
  end

  test "usuário comum não acessa a página do mecânico" do
    user = users(:one)
    user.update!(role: :user)
    sign_in user

    get mechanic_tasks_path

    assert_redirected_to root_path
  end

  test "mecânico não é tratado como usuário de setor na home" do
    user = users(:one)
    user.update!(role: :mechanical, sector: :fleet)
    sign_in user

    assert_not user.sector_fleet?
    get root_path

    assert_redirected_to mechanic_tasks_path
  end

  test "busca pelo título sem diferenciar maiúsculas e trata curingas como texto" do
    sign_in_mechanic
    tasks(:one).update_columns(title: "Revisão de freios 100%", completed: false)
    tasks(:two).update_columns(title: "Revisão de freios 100%", completed: false)

    get mechanic_tasks_path, params: { q: "  FREIOS 100%  " }

    assert_response :success
    assert_select ".mechanic-task", count: 1
    assert_select "#mechanic-task-#{tasks(:one).id} h3", "Revisão de freios 100%"
    assert_select "input[name=q][value='FREIOS 100%']"
    assert_select "input[name='label_ids[]']", count: 1

    get mechanic_tasks_path, params: { q: "100_" }
    assert_select ".mechanic-task", count: 0
    assert_select ".mechanic-tasks-empty h3", "Nenhuma OS encontrada"
  end

  test "combina plano título e qualquer um dos badges sem duplicar OS" do
    sign_in_mechanic
    task = tasks(:one)
    task.update_columns(title: "Freios dianteiros", completed: false)
    extra = task.bucket.action_plan.labels.create!(name: "Urgente", color: "#ef4444")
    task.task_labels.create!(label: extra)
    other = create_assigned_task(title: "Freios traseiros", label_ids: [extra.id])

    get mechanic_tasks_path, params: { q: "freios", action_plan_id: task.bucket.action_plan_id, label_ids: [labels(:one).id, extra.id] }

    assert_response :success
    assert_select ".mechanic-task", count: 2
    assert_select "#mechanic-task-#{task.id}", count: 1
    assert_select "#mechanic-task-#{other.id}", count: 1
    assert_select ".mechanic-task-stat.is-primary strong", "2"

    get mechanic_tasks_path, params: { action_plan_id: action_plans(:two).id, label_ids: [extra.id] }
    assert_select ".mechanic-task", count: 0

    get mechanic_tasks_path, params: { label_ids: [labels(:two).id] }
    assert_select ".mechanic-task", count: 0
  end

  test "resumo acompanha os filtros e mantém contagens de todos os status" do
    sign_in_mechanic
    tasks(:one).update_columns(title: "Freios abertos", completed: false, due_at: 1.day.ago)
    create_assigned_task(title: "Freios revisados", completed: true, due_at: 2.days.ago)
    create_assigned_task(title: "Pneus", completed: false)

    get mechanic_tasks_path, params: { q: "freios", status: "completed" }

    assert_response :success
    assert_select ".mechanic-task", count: 1
    assert_select ".mechanic-task.is-completed", count: 1
    assert_select ".mechanic-task-stat.is-primary strong", "1"
    assert_select ".mechanic-task-stat.is-overdue strong", "1"
    assert_select ".mechanic-task-stat.is-success strong", "1"
    assert_select ".mechanic-task-stat:last-child strong", "2"
  end

  test "kanban separa as etapas de planos diferentes e lista preserva os filtros" do
    sign_in_mechanic
    tasks(:one).update_columns(completed: false)
    tasks(:two).update_columns(completed: false)
    TaskAssignment.create!(task: tasks(:two), user: users(:one))

    get mechanic_tasks_path, params: { status: "all" }

    assert_response :success
    assert_select ".mechanic-tasks-board", count: 1
    assert_select ".mechanic-tasks-column", count: 2
    assert_select "#mechanic-column-#{buckets(:one).id}", count: 1
    assert_select "#mechanic-column-#{buckets(:two).id}", count: 1

    filters = { status: "all", view: "list", q: "MyString", label_ids: [labels(:one).id.to_s] }
    get mechanic_tasks_path, params: filters
    assert_select ".mechanic-tasks-list .mechanic-task", count: 1
    assert_select ".mechanic-tasks-view-switch a[href=?]", mechanic_tasks_path(filters.merge(view: "kanban"))
    assert_select ".mechanic-tasks-filters a[href=?]", mechanic_tasks_path(filters.merge(status: "completed"))

    get mechanic_tasks_path, params: { status: "invalid", view: "invalid", label_ids: ["", "invalid"] }
    assert_response :success
    assert_select ".mechanic-tasks-board", count: 1
    assert_select ".mechanic-tasks-filters a.is-active", text: /Abertas/
  end

  test "ações da OS retornam ao painel com os filtros e a visualização" do
    sign_in_mechanic
    task = tasks(:one)
    task.update_columns(completed: false)
    filters = { status: "all", view: "list", q: task.title, action_plan_id: task.bucket.action_plan_id.to_s, label_ids: [labels(:one).id.to_s] }
    expected_path = mechanic_tasks_path(filters)

    patch toggle_complete_action_plan_bucket_task_path(task.bucket.action_plan, task.bucket, task), params: { mechanic_filters: filters }
    assert task.reload.completed?
    assert_redirected_to expected_path

    post action_plan_bucket_task_comments_path(task.bucket.action_plan, task.bucket, task), params: { comment: { content: "Freios revisados" }, mechanic_filters: filters }
    assert_redirected_to expected_path

    post action_plan_bucket_task_tasklist_items_path(task.bucket.action_plan, task.bucket, task), params: { tasklist_item: { content: "Pastilhas" }, mechanic_filters: filters }
    assert_redirected_to expected_path
    item = task.tasklist.tasklist_items.order(:id).last
    assert_equal "Pastilhas", item.content

    patch action_plan_bucket_task_tasklist_item_path(task.bucket.action_plan, task.bucket, task, item), params: { tasklist_item: { content: "Pastilhas novas", completed: "true" }, mechanic_filters: filters }
    assert item.reload.completed?
    assert_equal "Pastilhas novas", item.content
    assert_redirected_to expected_path
  end

  test "filtros de retorno não permitem alterar OS de outro mecânico" do
    sign_in_mechanic
    task = tasks(:two)

    patch toggle_complete_action_plan_bucket_task_path(task.bucket.action_plan, task.bucket, task), params: { mechanic_filters: { status: "all" } }
    assert_response :not_found
  end

  private

  def sign_in_mechanic
    users(:one).update!(role: :mechanical, name: "Mecânico de teste")
    sign_in users(:one)
  end

  def create_assigned_task(**attributes)
    Task.create!({ bucket: buckets(:one), creator: users(:one), user_ids: [users(:one).id], completed: false }.merge(attributes))
  end
end
