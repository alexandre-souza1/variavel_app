require "test_helper"

class AiAssistantPageContextTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(role: :user, sector: :fleet)
    @plan = users(:two).action_plans.create!(name: "Plano restrito", sector: :warehouse, public: false)
    @task = @plan.buckets.first.tasks.create!(title: "Revisar pneus", creator: users(:two))
  end

  test "plan task and vehicle references follow current permissions without trusting labels from the browser" do
    [reference("plan", @plan.id), reference("task", @task.id), reference("unknown", @task.id),
     reference("task", -1), reference("task", 1.5)].each do |value|
      assert_raises(AiAssistant::PageContext::Unavailable) { context(value) }
    end
    @task.users << @user
    data = context(reference("task", @task.id).merge("label" => "Nome forjado", "role" => "admin")).client_data
    assert_equal "Tarefa: Revisar pneus", data[:label]
    assert_equal %w[type id].sort, data[:reference].keys.sort
    assert_includes data[:shortcuts].pluck(:label), "Concluir tarefa"
    plan_data = context(reference("plan", @plan.id)).model_data
    assert_equal @plan.id, plan_data["id"]
    @user.update!(sector: :warehouse)
    assert_raises(AiAssistant::PageContext::Unavailable) { context(reference("plate", plates(:one).id)) }
    @user.update!(role: :admin)
    assert_match(/Veículo:/, context(reference("plate", plates(:one).id)).client_data[:label])
  end

  test "mechanics see shortcuts for assigned tasks and cannot reference another inbox even as admin" do
    @task.users << @user
    @user.update!(role: :mechanical)
    assert_equal ["Resumir tarefa", "Alterar prazo", "Concluir tarefa"], context(reference("task", @task.id)).client_data[:shortcuts].pluck(:label)
    assert_equal ["Resumir plano", "Ver pendências"], context(reference("plan", @plan.id)).client_data[:shortcuts].pluck(:label)
    @task.update!(completed: true)
    assert_includes context(reference("task", @task.id)).client_data[:shortcuts].pluck(:label), "Reabrir tarefa"
    other = users(:two).personal_inbox!.tasks.create!(title: "Segredo", creator: users(:two))
    @user.update!(role: :admin)
    assert_raises(AiAssistant::PageContext::Unavailable) { context(reference("task", other.id)) }
    assert_empty context({}).client_data
  end

  private

  def reference(type, id)
    { "type" => type, "id" => id }
  end

  def context(value)
    AiAssistant::PageContext.new(user: @user, reference: value)
  end
end
