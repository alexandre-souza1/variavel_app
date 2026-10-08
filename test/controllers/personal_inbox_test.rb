require "test_helper"

class PersonalInboxTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other = users(:two)
    @user.update!(name: "Criador")
    @other.update!(name: "Responsável")
    @plan = @user.action_plans.create!(name: "Plano A")
    @second_plan = @user.action_plans.create!(name: "Plano B")
    @inbox = @user.personal_inbox!
    @task = @inbox.tasks.create!(title: "Ideia pessoal", creator: @user)
    @other_task = @other.personal_inbox!.tasks.create!(title: "Ideia privada alheia", creator: @other, users: [@user])
  end

  test "the same personal inbox appears in all plans and stays outside plan totals" do
    assert_empty @plan.buckets.where(inbox: true)
    assert_nil @inbox.action_plan_id
    %w[inbox kanban list].each do |view|
      [@plan, @second_plan].each do |plan|
        get action_plan_path(plan, view: view)
        assert_response :success
        assert_select "#open-tasks-#{@inbox.id} #task_#{@task.id}", count: 1
        assert_select "#task_#{@other_task.id}", count: 0
      end
    end
    get action_plan_path(@plan, view: "dashboard")
    assert_select ".plan-dashboard__metric", text: /0Total de tarefas/
  end

  test "a user can capture tasks before creating any plan" do
    newcomer = User.create!(name: "Novo usuário", email: "inbox-new@example.test", password: "password", sector: :fleet)
    assert_empty newcomer.action_plans
    sign_in newcomer
    get inbox_path
    assert_response :success
    post tasks_path, params: { task: { title: "Primeira ideia" } }
    assert_redirected_to inbox_path
    assert_equal ["Primeira ideia"], newcomer.personal_inbox!.tasks.pluck(:title)
  end

  test "inbox works before a user creates a plan and creation cannot override its owner or destination" do
    assert_difference("Task.count", 1) do
      post tasks_path, params: { task: { title: "Rascunho", bucket_id: @second_plan.buckets.first.id, creator_id: @other.id, label_ids: [labels(:one).id] } }, as: :turbo_stream
    end
    assert_response :success
    created = Task.find_by!(title: "Rascunho")
    assert_equal @inbox, created.bucket
    assert_equal @user, created.creator
    assert_empty created.labels
    get inbox_path
    assert_response :success
    assert_select "#task_#{created.id}"
    assert_select 'form[action=?]', tasks_path
  end

  test "admin and assignee cannot read edit complete comment or change another personal task" do
    get task_path(@other_task)
    assert_response :not_found
    sign_in @user
    patch task_path(@other_task), params: { task: { title: "Invadida" } }, as: :turbo_stream
    assert_response :not_found
    sign_in @user
    patch toggle_complete_task_path(@other_task), as: :turbo_stream
    assert_response :not_found
    sign_in @user
    patch move_task_path(@other_task), params: { bucket_id: @plan.buckets.first.id, position: 0 }
    assert_response :not_found
    sign_in @user
    post task_comments_path(@other_task), params: { comment: { content: "Invadida" } }, as: :turbo_stream
    assert_response :not_found
    sign_in @user
    post task_tasklist_items_path(@other_task), params: { tasklist_item: { content: "Invadida" } }, as: :turbo_stream
    assert_response :not_found
    sign_in @user
    delete task_tasklist_path(@other_task), as: :turbo_stream
    assert_response :not_found
    assert_equal "Ideia privada alheia", @other_task.reload.title
    assert @other_task.tasklist
  end

  test "modal comments checklist reminder and completion work without a plan" do
    get task_path(@task, action_plan_id: @plan.id)
    assert_response :success
    assert_select "select[name='task[bucket_id]'] option[value=?]", @plan.buckets.first.id.to_s
    assert_select "select[name='task[label_ids][]']", count: 0
    post task_comments_path(@task), params: { comment: { content: "Anotação privada" } }, as: :turbo_stream
    assert_response :success
    post task_tasklist_items_path(@task), params: { tasklist_item: { content: "Conferir" } }, as: :turbo_stream
    assert_response :success
    item = @task.tasklist.tasklist_items.last
    patch task_tasklist_item_path(@task, item), params: { tasklist_item: { completed: true } }, as: :turbo_stream
    assert_response :success
    assert item.reload.completed?
    patch task_path(@task), params: { task: { due_at: 4.days.from_now, due_notification_enabled: true } }, as: :turbo_stream
    assert_response :success
    patch toggle_complete_task_path(@task), as: :turbo_stream
    assert_response :success
    assert @task.reload.completed?
    assert_select "turbo-stream[target='open-tasks-#{@inbox.id}'] #task_#{@task.id}"
    get inbox_path
    assert_select "#task_#{@task.id}"
  end

  test "launching into a plan and returning preserves task identity and details" do
    @task.comments.create!(user: @user, content: "Preservar conversa")
    @task.tasklist.tasklist_items.create!(content: "Preservar checklist")
    patch move_task_path(@task), params: { bucket_id: @second_plan.buckets.first.id, position: 0, action_plan_id: @second_plan.id }
    assert_response :success
    assert_equal @second_plan.buckets.first, @task.reload.bucket
    get action_plan_path(@plan, view: "inbox")
    assert_select "#task_#{@task.id}", count: 0
    @task.labels << @second_plan.labels.create!(name: "Só deste plano", color: "#3616b6")
    patch task_path(@task), params: { task: { bucket_id: @inbox.id } }, as: :turbo_stream
    assert_response :success
    assert_equal @inbox, @task.reload.bucket
    assert_empty @task.labels
    assert_equal "Preservar conversa", @task.comments.last.content
    assert_equal "Preservar checklist", @task.tasklist.tasklist_items.last.content
  end

  test "both move and edit reject foreign plans foreign inboxes and contextual destination mismatches" do
    inaccessible = @other.action_plans.create!(name: "Restrito", sector: :warehouse, public: false)
    @user.update!(role: :user, sector: :fleet)
    sign_in @user
    [inaccessible.buckets.first, @other.personal_inbox!].each do |bucket|
      sign_in @user
      patch move_task_path(@task), params: { bucket_id: bucket.id, position: 0 }
      assert_response :not_found
      sign_in @user
      patch task_path(@task), params: { task: { bucket_id: bucket.id } }, as: :turbo_stream
      assert_response :not_found
    end
    sign_in @user
    patch task_path(@task, action_plan_id: @plan.id), params: { task: { bucket_id: @second_plan.buckets.first.id } }, as: :turbo_stream
    assert_response :forbidden
    assert_equal @inbox, @task.reload.bucket
    @task.update!(bucket: @plan.buckets.first)
    patch move_task_path(@task), params: { bucket_id: @second_plan.buckets.first.id, position: 0 }
    assert_response :forbidden
    patch task_path(@task), params: { task: { bucket_id: @second_plan.buckets.first.id } }, as: :turbo_stream
    assert_response :forbidden
    assert_equal @plan.buckets.first, @task.reload.bucket
  end

  test "only the creator can return a planned task to their inbox" do
    planned = @plan.buckets.first.tasks.create!(creator: @other, title: "Tarefa do colega")
    patch move_task_path(planned), params: { bucket_id: @inbox.id, position: 0 }
    assert_response :forbidden
    patch task_path(planned), params: { task: { bucket_id: @inbox.id } }, as: :turbo_stream
    assert_response :forbidden
    assert_equal @plan.buckets.first, planned.reload.bucket
  end

  test "gerot actions cannot be detached into an inbox" do
    template = Routines::PlanTemplateBuilder.call(action_plan: @plan, attributes: { name: "Modelo" })
    category = template.routine_categories.find_by!(bucket: @plan.buckets.first)
    category.routine_indicators.create!(name: "Indicador", position: 0, calculation_type: :ranged, value_type: :decimal)
    routine = Routines::Generator.call(template: template, action_plan: @plan, created_by: @user,
      period_start: Date.current.beginning_of_month, period_end: Date.current.end_of_month)
    generated = @plan.buckets.first.tasks.create!(title: "Ação do GEROT", creator: @user, routine_value: routine.routine_values.first)
    patch move_task_path(generated), params: { bucket_id: @inbox.id, position: 0 }
    assert_response :forbidden
    patch task_path(generated), params: { task: { bucket_id: @inbox.id } }, as: :turbo_stream
    assert_response :forbidden
    assert_not generated.update(bucket: @inbox)
    assert_equal @plan.buckets.first, generated.reload.bucket
  end

  test "launching and assigning in the same edit notifies each new assignee once" do
    assert_difference("Notification.count", 1) do
      patch task_path(@task), params: { task: { bucket_id: @plan.buckets.first.id, user_ids: [@other.id] } }, as: :turbo_stream
    end
    assert_response :success
    assert_equal [@other.id], @task.reload.user_ids
    assert_select "turbo-stream[target='task-modal-content'] select[name='task[label_ids][]']"
  end

  test "invalid creation and update preserve the inbox and existing task details" do
    positions = @inbox.tasks.pluck(:id, :position)
    assert_no_difference("Task.count") do
      post tasks_path, params: { task: { title: "" } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_equal positions, @inbox.tasks.pluck(:id, :position)
    patch task_path(@task), params: { task: { title: "", bucket_id: @plan.buckets.first.id } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal @inbox, @task.reload.bucket
    assert_equal "Ideia pessoal", @task.title
  end

  test "nested routes must match the task bucket and plan" do
    post action_plan_bucket_tasks_path(@plan, @second_plan.buckets.first), params: { task: { title: "Destino forjado" } }, as: :turbo_stream
    assert_response :not_found
    sign_in @user
    get action_plan_bucket_task_path(@plan, @plan.buckets.first, @task)
    assert_response :not_found
    planned = @plan.buckets.first.tasks.create!(title: "Planejada", creator: @user)
    sign_in @user
    get action_plan_bucket_task_path(@second_plan, planned.bucket, planned)
    assert_response :not_found
  end

  test "plan deletion export bulk assignments and gerot templates do not affect the personal inbox" do
    patch assign_open_tasks_action_plan_path(@plan), params: { user_ids: [@other.id] }
    assert_empty @task.reload.users
    get export_excel_action_plan_path(@plan, format: :xlsx)
    assert_response :success
    template = Routines::PlanTemplateBuilder.call(action_plan: @plan, attributes: { name: "Modelo" })
    assert_not_includes template.routine_categories.pluck(:bucket_id), @inbox.id
    delete action_plan_path(@second_plan)
    assert_response :redirect
    assert_equal @inbox, @task.reload.bucket
  end
end
