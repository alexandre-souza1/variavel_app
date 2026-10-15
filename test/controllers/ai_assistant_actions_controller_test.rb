require "test_helper"
require "minitest/mock"

class AiAssistantActionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(role: :user, sector: :fleet, name: "Ana")
    @conversation = AiConversation.create!(user: @user)
  end

  test "requires login and isolates proposals and confirmation tokens between accounts" do
    action = proposal("create_task", title: "Privada")
    sign_out @user
    post confirm_ai_assistant_action_path(action), params: { confirmation_token: action.confirmation_token }, as: :json
    assert_response :unauthorized
    post cancel_ai_assistant_action_path(action), as: :json
    assert_response :unauthorized
    sign_in users(:two)
    assert_no_difference "Task.count" do
      post confirm_ai_assistant_action_path(action), params: { confirmation_token: action.confirmation_token, user_id: @user.id }, as: :json
      assert_response :not_found
      post cancel_ai_assistant_action_path(action), as: :json
      assert_response :not_found
    end
    get ai_assistant_path, params: { conversation_id: @conversation.id }, as: :json
    refute_includes response.body, action.confirmation_token
    assert_empty response.parsed_body["messages"]
  end

  test "confirmation creates exactly the previewed task once and records the actor and source" do
    plan = @user.action_plans.create!(name: "Revisão frota", public: false)
    action = proposal("create_task", title: "Verificar pneus", description: "Conferir sulcos",
      plan_id: plan.id, bucket_id: plan.buckets.first.id,
      due_at: "2030-10-20T14:00:00-03:00", user_ids: [users(:two).id], checklist: ["Verificar pressão"])
    assert_difference "Task.count", 1 do
      post confirm_ai_assistant_action_path(action), params: { confirmation_token: action.confirmation_token,
        title: "Título forjado", user_id: users(:two).id, payload: { title: "Forjada" } }, as: :json
      assert_response :success
    end
    assert_includes response.headers["Cache-Control"], "no-store"
    task = Task.find(action.reload.result.fetch("id"))
    assert_equal "Verificar pneus", task.title
    assert_equal @user, task.creator
    assert_equal plan.buckets.first, task.bucket
    assert_equal [users(:two).id], task.user_ids
    assert_equal ["Verificar pressão"], task.tasklist.tasklist_items.pluck(:content)
    activity = task.task_activities.find_by!(activity_type: :created)
    assert_equal @user.id, activity.user_id
    assert_equal "ai_assistant", activity.metadata["source"]
    assert_equal action.id, activity.metadata["ai_action_request_id"]
    assert_equal "executed", action.status
    assert action.executed_at
    assert_equal "executed", response.parsed_body["messages"].last["actions"].first["status"]
    assert_no_difference ["Task.count", "TaskActivity.count", "Notification.count"] do
      post confirm_ai_assistant_action_path(action), params: { confirmation_token: action.confirmation_token }, as: :json
      assert_response :success
    end
  end

  test "preview tokens are required and expiry cancellation and clearing prevent creation" do
    action = proposal("create_task", title: "Pendente")
    assert_no_difference "Task.count" do
      [nil, "incorrect"].each do |token|
        post confirm_ai_assistant_action_path(action), params: { confirmation_token: token }, as: :json
        assert_response :unprocessable_entity
      end
      post cancel_ai_assistant_action_path(action), as: :json
      assert_response :success
      post confirm_ai_assistant_action_path(action), params: { confirmation_token: action.confirmation_token }, as: :json
      assert_response :conflict
      action = proposal("create_task", title: "Expirada")
      travel 31.minutes do
        post confirm_ai_assistant_action_path(action), params: { confirmation_token: action.confirmation_token }, as: :json
        assert_response :conflict
        get ai_assistant_path, as: :json
        assert_equal "expired", response.parsed_body["messages"].last["actions"].first["status"]
      end
      action = proposal("create_task", title: "Limpa")
      delete ai_assistant_path, as: :json
      assert_response :success
      assert_equal "cancelled", action.reload.status
      assert_nil action.ai_message_id
      post confirm_ai_assistant_action_path(action), params: { confirmation_token: action.confirmation_token }, as: :json
      assert_response :conflict
    end
  end

  test "confirming a personal task creates only the actors inbox and preserves its privacy" do
    @user.inbox_bucket&.destroy!
    action = proposal("create_task", title: "Lembrete pessoal", due_at: 2.hours.from_now.iso8601,
      reminder: true, user_ids: [users(:two).id])
    assert_difference({ "Bucket.count" => 1, "Task.count" => 1 }) do
      confirm(action)
      assert_response :success
    end
    task = Task.find(action.reload.result.fetch("id"))
    assert task.inbox?
    assert_equal @user.id, task.bucket.user_id
    assert_equal @user, task.creator
    assert task.due_notification_enabled?
    refute Task.accessible_to(users(:two)).exists?(task.id)
    assert_equal [@user.id], Notification.where(notifiable: task).pluck(:user_id).uniq
  end

  test "permissions assignees and previewed destination are checked again on confirmation" do
    plan = users(:two).action_plans.create!(name: "Compartilhado", sector: :warehouse, public: true)
    action = proposal("create_task", title: "Teste", plan_id: plan.id, bucket_id: plan.buckets.first.id)
    plan.update!(public: false)
    assert_no_difference "Task.count" do
      confirm(action)
      assert_response :forbidden
      plan.update!(public: true)
      plan.update!(sector: :fleet, public: false)
      confirm(action)
      assert_response :conflict
      plan.update!(sector: :warehouse, public: true)
      plan.buckets.first.update!(name: "Destino diferente")
      confirm(action)
      assert_response :conflict
      @user.update!(role: :mechanical)
      confirm(action)
      assert_response :forbidden
    end
    @user.update!(role: :user)
    action = proposal("create_task", title: "Equipe", user_ids: [users(:two).id])
    users(:two).update!(active: false)
    assert_no_difference "Task.count" do
      confirm(action)
      assert_response :forbidden
    end
  end

  test "plan with initial tasks is atomic and its audit survives clearing the conversation" do
    action = proposal("create_plan", name: "Revisão mensal", description: "Plano da equipe", tasks: [
      { title: "Inspecionar pneus", due_at: "2030-10-20", reminder: true },
      { title: "Conferir pressão", checklist: ["Eixo dianteiro", "Eixo traseiro"] }
    ])
    assert_difference({ "ActionPlan.count" => 1, "Task.count" => 2, "Bucket.count" => 3 }) do
      confirm(action)
      assert_response :success
    end
    plan = ActionPlan.find(action.reload.result.fetch("id"))
    assert_equal @user, plan.user
    assert_equal @user.sector, plan.sector
    refute plan.public?
    assert_equal ["A Fazer", "Em Andamento", "Concluído"], plan.buckets.pluck(:name)
    assert_equal 2, plan.buckets.first.tasks.count
    assert_equal ["Inspecionar pneus", "Conferir pressão"], plan.buckets.first.tasks.order(:position).pluck(:title)
    assert plan.buckets.first.tasks.all? { |task| task.creator == @user }
    assert_equal 2, TaskActivity.where(task_id: action.result["task_ids"]).count
    post cancel_ai_assistant_action_path(action), as: :json
    assert_response :conflict
    delete ai_assistant_path, as: :json
    assert_response :success
    assert_equal "executed", action.reload.status
    assert_nil action.ai_message_id
    assert_equal @user.id, action.user_id
    assert ActionPlan.exists?(plan.id)
  end

  test "a failure midway through a plan leaves no partial records and allows retry" do
    action = proposal("create_plan", name: "Atômico", tasks: [{ title: "Primeira" }, { title: "Segunda" }])
    calls = 0
    log = lambda do |**args|
      calls += 1
      raise ActiveRecord::RecordInvalid.new(args[:task]) if calls == 2
      TaskActivity.create!(**args)
    end
    assert_no_difference ["ActionPlan.count", "Bucket.count", "Task.count", "TaskActivity.count", "Notification.count"] do
      TaskActivityService.stub(:log, log) { confirm(action) }
      assert_response :unprocessable_entity
    end
    assert_equal "pending", action.reload.status
    assert_empty action.result
    confirm(action)
    assert_response :success
    assert_equal "executed", action.reload.status
  end

  test "replaced proposals cancel older drafts while stale job completions cannot persist proposals" do
    old = proposal("create_task", title: "Antiga")
    action = proposal("create_task", title: "Corrigida")
    assert_equal "cancelled", old.reload.status
    assert_equal "pending", action.status
    draft = AiAssistant::ActionDraft.new(user: @user, kind: "create_task", arguments: { title: "Obsoleta" })
    assert_no_difference "AiActionRequest.count" do
      @conversation.finish!("stale-token", answer: { content: "Obsoleta", sources: [], actions: [draft.to_h] })
    end
    tools = AiAssistant::Tools.new(@user)
    pending = tools.call("pending_actions", {})
    assert_equal ["Corrigida"], pending[:proposals].map { |item| item[:data]["title"] }
    refute_includes pending.to_json, action.confirmation_token
  end

  private

  def proposal(kind, **arguments)
    draft = AiAssistant::ActionDraft.new(user: @user, kind: kind, arguments: arguments)
    @conversation.update!(request_token: "ready", requested_at: Time.current)
    @conversation.finish!("ready", answer: { content: "Confira a prévia.", sources: [], actions: [draft.to_h] })
    @conversation.ai_action_requests.order(:id).last
  end

  def confirm(action)
    post confirm_ai_assistant_action_path(action), params: { confirmation_token: action.confirmation_token }, as: :json
  end
end
