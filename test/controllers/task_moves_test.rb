require "test_helper"
require "minitest/mock"

class TaskMovesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(name: "Criador")
    @plan = @user.action_plans.create!(name: "Movimentação")
    @source, @destination = @plan.buckets.work.order(:position).first(2)
    @task = @source.tasks.create!(title: "Mover", creator: @user)
  end

  test "drag commits the final bucket and position with one card confirmation" do
    first = @destination.tasks.create!(title: "Primeira", creator: @user)
    last = @destination.tasks.create!(title: "Última", creator: @user)
    messages = capture_moves do
      move_to(@destination, position: 1)
    end
    assert_response :success
    assert_equal [first.id, @task.id, last.id], @destination.tasks.order(:position).pluck(:id)
    assert_equal 1, @task.task_activities.bucket_changed.count
    assert_select "turbo-stream[action=task_move][target='open-tasks-#{@destination.id}'][position='1'] template #task_#{@task.id}"
    assert_select "turbo-stream[action=remove], turbo-stream[action=prepend]", count: 0
    assert_equal 1, messages.size
    assert_equal "tasks_action_plan_#{@plan.id}", messages.first[:stream]
    assert_equal @task.reload.updated_at.iso8601(6), messages.first[:attributes]["version"]
    assert_equal ["task_#{first.id}"], JSON.parse(messages.first[:attributes]["preceding-task-ids"])
  end

  test "completed cards do not change the requested open-card position" do
    @destination.tasks.create!(title: "Concluída", creator: @user, completed: true)
    first = @destination.tasks.create!(title: "Primeira aberta", creator: @user)
    last = @destination.tasks.create!(title: "Última aberta", creator: @user)
    move_to(@destination, position: 1)
    assert_response :success
    assert_equal [first.id, @task.id, last.id], @destination.tasks.where(completed: false).order(:position).pluck(:id)
    assert_select "turbo-stream[action=task_move][position='1']"
  end

  test "changing buckets through the modal also confirms one stable move" do
    first = @destination.tasks.create!(title: "Já no destino", creator: @user)
    messages = capture_moves do
      patch task_path(@task), params: { action_plan_id: @plan.id, task: { bucket_id: @destination.id } }, as: :turbo_stream
    end
    assert_response :success
    assert_equal [first.id, @task.id], @destination.tasks.order(:position).pluck(:id)
    assert_equal 1, messages.size
    assert_select "turbo-stream[action=task_move][target='open-tasks-#{@destination.id}'] template #task_#{@task.id}"
    assert_select "turbo-stream[action=update][target=task-modal-content]"
    assert_select "turbo-stream[action=replace][target='task_#{@task.id}']", count: 0
  end

  test "a completed inbox task can be dropped beside open plan cards and keeps its status" do
    @task.update!(bucket: @user.personal_inbox!, completed: true)
    open_task = @destination.tasks.create!(title: "Aberta", creator: @user)
    move_to(@destination, position: 0, following_task_id: open_task.id)
    assert_response :success
    assert_equal @destination.id, @task.reload.bucket_id
    assert @task.completed?
    assert_select "turbo-stream[action=task_move][target='done-tasks-#{@destination.id}'] template #task_#{@task.id}"
  end

  test "reordering within the same bucket keeps the final order in both directions" do
    second = @source.tasks.create!(title: "Segunda", creator: @user)
    third = @source.tasks.create!(title: "Terceira", creator: @user)
    messages = capture_moves { move_to(@source, position: 2, preceding_task_id: third.id) }
    assert_response :success
    assert_equal [second.id, third.id, @task.id], @source.tasks.order(:position).pluck(:id)
    assert_equal 1, messages.size
    move_to(@source, position: 0, following_task_id: second.id)
    assert_response :success
    assert_equal [@task.id, second.id, third.id], @source.tasks.order(:position).pluck(:id)
    assert_empty @task.task_activities.bucket_changed
  end

  test "returning to inbox never sends private card content to the old plan" do
    inbox = @user.personal_inbox!
    messages = capture_moves { move_to(inbox, position: 0) }
    assert_response :success
    assert_equal inbox.id, @task.reload.bucket_id
    old_plan = messages.find { |message| message[:stream] == "tasks_action_plan_#{@plan.id}" }
    assert_equal false, old_plan[:render]
    assert_nil old_plan[:partial]
    assert_equal %w[task-id version], old_plan[:attributes].keys.sort
    own_inbox = messages.find { |message| message[:stream] == "tasks_inbox_#{@user.id}" }
    assert_equal "tasks/task", own_inbox[:partial]
    assert_equal 2, messages.size
  end

  test "a sibling from another bucket rejects the move without changing the task" do
    foreign = @source.tasks.create!(title: "Outro bucket", creator: @user)
    assert_no_difference("TaskActivity.count") do
      move_to(@destination, position: 0, following_task_id: foreign.id)
    end
    assert_response :not_found
    assert_equal @source.id, @task.reload.bucket_id
    assert_equal 1, @task.position
  end

  test "GEROT drag broadcasts one move instead of removing and prepending the card" do
    routine = routines(:one)
    routine.routine_template.update!(action_plan: @plan, sector: @plan.sector)
    routine.update!(action_plan: @plan)
    @task.update!(routine_value: routine_values(:one))
    messages = capture_moves { move_to(@destination, position: 0, view: "gerot_actions", routine_id: routine.id) }
    assert_response :success
    assert_equal 3, messages.size
    assert_equal [["tasks_action_plan_#{@plan.id}"], [@plan, :gerot_tasks], [routine, :gerot_tasks]],
      messages.map { |message| message[:streamables] }
  end

  private

  def move_to(destination, **attributes)
    patch move_task_path(@task), params: { bucket_id: destination.id, action_plan_id: @plan.id, **attributes }, as: :turbo_stream
  end

  def capture_moves
    messages = []
    broadcaster = ->(*streamables, **attributes) { messages << { stream: streamables.first, streamables: streamables, **attributes } }
    Turbo::StreamsChannel.stub(:broadcast_action_to, broadcaster) do
      yield
    end
    assert_not messages.any? { |message| %i[remove prepend].include?(message[:action]) &&
      ["task_#{@task.id}", "open-tasks-#{@task.reload.bucket_id}"].include?(message[:target]) }
    # Count and activity streams have their own actions; only card movement
    # should produce a task_move confirmation for each subscribed stream.
    messages.select { |message| message[:action] == :task_move }
  end
end
