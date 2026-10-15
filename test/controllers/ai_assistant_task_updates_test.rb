require "test_helper"
require "minitest/mock"

class AiAssistantTaskUpdatesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(role: :user, sector: :fleet, name: "Ana")
    users(:two).update!(name: "Bruno")
    @conversation = AiConversation.create!(user: @user)
    @plan = users(:two).action_plans.create!(name: "Revisão", public: true)
    @task = @plan.buckets.first.tasks.create!(title: "Conferir pneus", description: "Descrição original",
      creator: users(:two), due_at: "2030-10-20T14:00:00-03:00", user_ids: [@user.id])
  end

  test "previews only requested changes without touching records and preserves omitted associations" do
    label = @plan.labels.create!(name: "Pneus", color: "#123456")
    @task.labels << label
    @task.tasklist.tasklist_items.create!(content: "Verificar pressão", completed: false)
    tools = AiAssistant::Tools.new(@user)
    result = nil
    assert_no_difference ["Task.count", "TaskActivity.count", "Notification.count", "AiActionRequest.count"] do
      result = tools.call("prepare_task_update", { task_id: @task.id, changes: { due_at: "2030-10-21" } })
    end
    assert result[:confirmation_required]
    assert_equal false, result[:executed]
    changes = result[:preview]["changes"]
    assert_equal ["Prazo"], changes.pluck("label")
    assert_includes changes.first["before"], "20/10/2030 às 14:00"
    assert_includes changes.first["after"], "21/10/2030 às 23:59"
    assert_equal "2030-10-20T14:00:00-03:00", @task.reload.due_at.iso8601
    action = persist(tools.drafts.sole)
    assert_no_difference "Task.count" do
      confirm(action)
      assert_response :success
    end
    assert_equal [@user.id], @task.reload.user_ids
    assert_equal [label.id], @task.label_ids
    assert_equal ["Verificar pressão"], @task.tasklist.tasklist_items.pluck(:content)
    assert_equal "Descrição original", @task.description
    assert_equal "2030-10-21T23:59:59-03:00", @task.due_at.iso8601
    assert_equal "due_date_changed", @task.task_activities.sole.activity_type
  end

  test "updates title description assignees dates and reminders with actor audit and no duplicate writes" do
    action = proposal(title: "Revisar pneus", description: "Verificar os sulcos", user_ids: [users(:two).id],
      start_at: "2030-10-19", due_at: "2030-10-21T15:00:00-03:00", reminder: true)
    assert_no_difference "Task.count" do
      confirm(action, changes: { title: "Forjado" }, user_id: users(:two).id)
      assert_response :success
    end
    assert_equal "Revisar pneus", @task.reload.title
    assert_equal "Verificar os sulcos", @task.description
    assert_equal [users(:two).id], @task.user_ids
    assert @task.due_notification_enabled?
    assert_equal "2030-10-19T00:00:00-03:00", @task.start_at.iso8601
    assert_equal 7, @task.task_activities.count
    assert @task.task_activities.all? { |entry| entry.user_id == @user.id && entry.metadata["ai_action_request_id"] == action.id }
    assert_equal %w[assignee_added assignee_removed description_changed due_date_changed start_date_changed updated updated].sort,
      @task.task_activities.pluck(:activity_type).sort
    assert_equal "update_task", response.parsed_body["messages"].last["actions"].first["kind"]
    version = @task.updated_at
    assert_no_difference ["TaskActivity.count", "Notification.count"] do
      confirm(action)
      assert_response :success
    end
    assert_equal version, @task.reload.updated_at
  end

  test "completion and reopening set explicit states and repeated requests never toggle them" do
    complete = proposal(completed: true)
    confirm(complete)
    assert_response :success
    assert @task.reload.completed?
    completed_at = @task.completed_at
    confirm(complete)
    assert_response :success
    assert_equal completed_at, @task.reload.completed_at
    assert_equal 1, @task.task_activities.where(activity_type: :completed).count
    reopen = proposal(completed: false)
    confirm(reopen)
    assert_response :success
    refute @task.reload.completed?
    assert_nil @task.completed_at
    assert_equal 1, @task.task_activities.where(activity_type: :reopened).count
    assert AiAssistant::Tools.new(@user).call("prepare_task_update", { task_id: @task.id, changes: { completed: false } })[:error]
  end

  test "completing recurring tasks discloses and preserves the existing next occurrence flow" do
    @task.update!(recurrence: "weekly", clone_tasklist_on_recurrence: true)
    @task.tasklist.tasklist_items.create!(content: "Calibrar", completed: true)
    action = proposal(completed: true)
    assert_match(/recorrência/, action.preview["notices"].sole)
    assert_difference "Task.count", 1 do
      confirm(action)
      assert_response :success
    end
    next_task = @plan.buckets.first.tasks.where.not(id: @task.id).sole
    assert_equal @task.reload.due_at + 1.week, next_task.due_at
    assert_equal @task.user_ids, next_task.user_ids
    assert_equal [false], next_task.tasklist.tasklist_items.pluck(:completed)
    assert_no_difference "Task.count" do
      confirm(action)
      assert_response :success
    end
  end

  test "stale fields and association changes without a timestamp update block confirmation" do
    action = proposal(due_at: "2030-10-21")
    version = @task.updated_at
    @task.users = [users(:two)]
    assert_equal version, @task.reload.updated_at
    assert_no_difference "TaskActivity.count" do
      confirm(action)
      assert_response :conflict
    end
    assert_equal "2030-10-20T14:00:00-03:00", @task.reload.due_at.iso8601
    action = proposal(description: "Nova descrição")
    @task.update_columns(title: "Editada por outra pessoa")
    confirm(action)
    assert_response :conflict
    assert_equal "Descrição original", @task.reload.description
    assert_equal "pending", action.reload.status
  end

  test "loss of access inactive assignees cancellation expiry and clearing prevent updates" do
    action = proposal(user_ids: [users(:two).id])
    users(:two).update!(active: false)
    confirm(action)
    assert_response :forbidden
    users(:two).update!(active: true)
    @plan.update!(public: false, sector: :warehouse)
    @task.users = []
    confirm(action)
    assert_response :forbidden
    @plan.update!(public: true)
    action = proposal(completed: true)
    post cancel_ai_assistant_action_path(action), as: :json
    confirm(action)
    assert_response :conflict
    action = proposal(completed: true)
    travel 31.minutes do
      confirm(action)
      assert_response :conflict
    end
    action = proposal(completed: true)
    delete ai_assistant_path, as: :json
    confirm(action)
    assert_response :conflict
    refute @task.reload.completed?
  end

  test "mechanics can update assigned tasks but cannot access other tasks or inboxes" do
    @user.update!(role: :mechanical)
    action = proposal(completed: true)
    confirm(action)
    assert_response :success
    assert @task.reload.completed?
    other = @plan.buckets.first.tasks.create!(title: "Outra", creator: users(:two))
    inbox = users(:two).personal_inbox!.tasks.create!(title: "Privada", creator: users(:two))
    tools = AiAssistant::Tools.new(@user)
    [other, inbox].each do |task|
      assert tools.call("task_details", { task_id: task.id })[:error]
      assert tools.call("prepare_task_update", { task_id: task.id, changes: { completed: true } })[:error]
    end
    assert tools.call("prepare_task", { title: "Indevida" })[:error]
  end

  test "forged fields invalid data and targets are rejected and admins cannot edit another personal inbox" do
    tools = AiAssistant::Tools.new(@user)
    [{ creator_id: @user.id }, { bucket_id: buckets(:one).id }, { completed_at: Time.current.iso8601 },
     { recurrence: "daily" }, { checklist: [] }, { completed: "true" }, { title: "" },
     { due_at: "2030-02-30" }, { start_at: "2030-10-22", due_at: "2030-10-21" }].each do |changes|
      assert tools.call("prepare_task_update", { task_id: @task.id, changes: changes })[:error], changes.inspect
    end
    assert tools.call("prepare_task_update", { task_id: @task.id, changes: { completed: true }, expected_state: {} })[:error]
    @user.update!(role: :admin)
    other = users(:two).personal_inbox!.tasks.create!(title: "Segredo", creator: users(:two))
    assert tools.call("prepare_task_update", { task_id: other.id, changes: { completed: true } })[:error]
    assert_empty tools.drafts
  end

  test "removing the due date discloses and disables its reminder" do
    @task.update!(due_notification_enabled: true)
    action = proposal(due_at: "")
    assert_equal ["Prazo", "Lembrete de vencimento"], action.preview["changes"].pluck("label")
    confirm(action)
    assert_response :success
    assert_nil @task.reload.due_at
    refute @task.due_notification_enabled?
  end

  test "an audit failure rolls back the edit and clearing retains successful update audits" do
    action = proposal(title: "Título corrigido")
    TaskActivityService.stub(:log, ->(**args) { raise ActiveRecord::RecordInvalid.new(args[:task]) }) do
      confirm(action)
      assert_response :unprocessable_entity
    end
    assert_equal "Conferir pneus", @task.reload.title
    assert_equal "pending", action.reload.status
    confirm(action)
    assert_response :success
    delete ai_assistant_path, as: :json
    assert_equal "executed", action.reload.status
    assert_nil action.ai_message_id
    assert_equal "Título corrigido", @task.reload.title
    assert_equal @user.id, @task.task_activities.sole.user_id
  end

  private

  def proposal(**changes)
    persist(AiAssistant::ActionDraft.build(user: @user, kind: "update_task", arguments: { task_id: @task.id, changes: changes }).to_h)
  end

  def persist(draft)
    @conversation.update!(request_token: "ready", requested_at: Time.current)
    @conversation.finish!("ready", answer: { content: "Confira a prévia.", sources: [], actions: [draft] })
    @conversation.ai_action_requests.order(:id).last
  end

  def confirm(action, **extra)
    post confirm_ai_assistant_action_path(action), params: extra.merge(confirmation_token: action.confirmation_token), as: :json
  end
end
