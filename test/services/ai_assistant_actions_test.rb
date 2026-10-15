require "test_helper"

class AiAssistantActionsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(role: :user, sector: :fleet, name: "Ana Frota")
    users(:two).update!(name: "Bruno")
    @tools = AiAssistant::Tools.new(@user)
    @plan = users(:two).action_plans.create!(name: "Plano Armazém", sector: :warehouse, public: false)
  end

  test "preparing a task resolves defaults dates and checklist without creating business records or an inbox" do
    @user.inbox_bucket&.destroy!
    result = nil
    assert_no_difference ["Task.count", "ActionPlan.count", "Bucket.count", "Notification.count", "AiActionRequest.count"] do
      result = @tools.call("prepare_task", { title: "Verificar pneus", due_at: "2030-10-20", reminder: true, checklist: ["Calibrar"] })
    end
    assert result[:confirmation_required]
    assert_equal false, result[:executed]
    payload = @tools.drafts.first[:payload]
    assert_equal [@user.id], payload["user_ids"]
    assert_equal "2030-10-20T23:59:59-03:00", payload["due_at"]
    assert_nil payload["plan_id"]
    assert_equal ["Calibrar"], payload["checklist"]
    assert_includes result[:preview]["details"].map { |field| field["value"] }, "Sua Entrada pessoal"
    refute_includes result.to_json, "confirmation_token"
    @tools.call("prepare_task", { title: "Verificar pneus", due_at: "2030-10-20", reminder: true, checklist: ["Calibrar"] })
    assert_equal 1, @tools.drafts.size
  end

  test "plan and bucket ids are scoped and another persons inbox cannot be selected" do
    assert @tools.call("prepare_task", { title: "Indevida", plan_id: @plan.id, bucket_id: @plan.buckets.first.id })[:error]
    assert @tools.call("action_options", { plan_id: @plan.id })[:error]
    @plan.update!(public: true)
    assert @tools.call("prepare_task", { title: "Indevida", plan_id: @plan.id, bucket_id: buckets(:one).id })[:error]
    assert @tools.call("prepare_task", { title: "Indevida", bucket_id: users(:two).personal_inbox!.id })[:error]
    assert_empty @tools.drafts
    options = @tools.call("action_options", { plan_id: @plan.id, assignee_query: "Bruno" })
    assert_equal @plan.buckets.pluck(:id), options[:plan_buckets].pluck(:id)
    assert_equal [users(:two).id], options[:assignees][:records].pluck(:id)
    refute options[:assignees][:records].any? { |account| account.key?(:email) }
  end

  test "only admins may select a different plan sector and actors cannot be forged" do
    assert @tools.call("prepare_plan", { name: "Plano", sector: "warehouse" })[:error]
    %w[user_id creator_id completed routine_value_id].each do |field|
      assert @tools.call("prepare_task", { title: "Forjada", field => users(:two).id })[:error]
    end
    assert @tools.call("prepare_plan", { name: "Forjado", user_id: users(:two).id })[:error]
    assert_empty @tools.drafts
    @user.update!(role: :admin)
    result = @tools.call("prepare_plan", { name: "Plano AZ", sector: "warehouse", tasks: [{ title: "Conferir", user_ids: [users(:two).id] }] })
    assert result[:confirmation_required]
    assert_equal "warehouse", @tools.drafts.last[:payload]["sector"]
    assert_equal false, @tools.drafts.last[:payload]["public"]
  end

  test "mechanics cannot create and inactive accounts cannot use action tools even with direct calls" do
    @user.update!(role: :mechanical)
    refute @tools.declarations.any? { |entry| entry[:name] == "prepare_task" }
    %w[prepare_task prepare_plan confirm_action].each do |name|
      assert @tools.call(name, { title: "Bloqueada", name: "Bloqueado" })[:error]
    end
    assert @tools.declarations.any? { |entry| entry[:name] == "prepare_task_update" }
    assert_equal false, @tools.call("action_options", {})[:can_create]
    assert_equal [], @tools.call("pending_actions", {})[:proposals]
    @user.update!(role: :user, active: false)
    assert @tools.call("prepare_task", { title: "Bloqueada" })[:error]
    assert_empty @tools.drafts
  end

  test "invalid dates reminder options oversized data and inactive assignees do not produce proposals" do
    users(:two).update!(active: false)
    [
      { title: "" }, { title: "x" * 201 }, { title: "Data", due_at: "amanhã" },
      { title: "Data", due_at: "2030-02-30" }, { title: "Lembrete", reminder: true },
      { title: "Lembrete", reminder: "false" }, { title: "Responsável", user_ids: [users(:two).id] },
      { title: "Data", start_at: "2030-10-30", due_at: "2030-10-01" },
      { title: "Checklist", checklist: [""] }, { title: "Checklist", checklist: ["x"] * 21 },
      { title: "Responsável", user_ids: [1.2] }
    ].each { |args| assert @tools.call("prepare_task", args)[:error], args.inspect }
    assert @tools.call("prepare_plan", { name: "Grande", tasks: [{ title: "x" }] * 11 })[:error]
    assert_empty @tools.drafts
  end
end
