require "test_helper"

class RoutineIndicatorAssigneesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @reader = users(:two)
    @reader.update!(role: :user, name: "Responsável")
    @plan = @owner.action_plans.create!(name: "Responsáveis GEROT")
    @template = Routines::PlanTemplateBuilder.call(action_plan: @plan)
    @indicator = @template.routine_categories.first.routine_indicators.create!(
      name: "Pendências", position: 0, value_type: :integer,
      calculation_type: :last_value, goal_direction: :less_or_equal
    )
    @indicator.routine_indicator_targets.create!(goal: "0", starts_at: Date.new(2026, 1, 1))
    @routine = generate(Date.new(2026, 10, 1))
    @value = @routine.routine_values.first
    @value.update!(value: "3")
  end

  test "owner saves multiple assignees shared across cells and periods" do
    @owner.update!(role: :user)
    assert_difference("RoutineIndicatorAssignment.count", 2) { assign([@owner.id, @reader.id, @reader.id]) }
    assert_response :success
    assert_equal [@owner.id, @reader.id].sort, @indicator.reload.user_ids.sort
    other_period = generate(Date.new(2026, 11, 1))
    [@routine.routine_values.last, other_period.routine_values.first].each do |value|
      get routine_value_routine_comments_path(value), as: :json
      assert_response :success
      assert response.parsed_body["can_manage_assignees"]
      assert_equal [@owner.id, @reader.id].sort, response.parsed_body["indicator_assignees"].map { |user| user["id"] }.sort
    end
  end

  test "comments inherit assignees and changes only affect new tasks with author fallback when cleared" do
    assign([@owner.id])
    sign_in @reader
    first_task = comment_task("Investigar causa")
    assert_equal [@owner.id], first_task.user_ids
    assert_equal @reader, first_task.creator
    sign_in @owner
    assign([@owner.id, @reader.id])
    second_task = comment_task("Outra causa")
    assert_equal [@owner.id, @reader.id].sort, second_task.user_ids.sort
    assert_equal [@owner.id], first_task.reload.user_ids
    assert_difference("RoutineIndicatorAssignment.count", -2) { assign([]) }
    assert_response :success
    assert_empty @indicator.reload.users
    sign_in @reader
    assert_equal [@reader.id], comment_task("Sem responsáveis fixos").user_ids
    assert_equal [@owner.id, @reader.id].sort, second_task.reload.user_ids.sort
  end

  test "value based generation also uses configured assignees" do
    assign([@owner.id, @reader.id])
    @routine.update!(task_generation_mode: :deviation)
    assert_difference("Task.count", 1) do
      patch routine_value_path(@value), params: { routine_value: { value: "4" } }, as: :json
    end
    assert_response :success
    assert_equal [@owner.id, @reader.id].sort, @value.generated_tasks.first.user_ids.sort
  end

  test "readers see assignees but cannot change them" do
    assign([@owner.id])
    sign_in @reader
    get routine_value_routine_comments_path(@value), as: :json
    assert_response :success
    assert_not response.parsed_body["can_manage_assignees"]
    assert_empty response.parsed_body["available_assignees"]
    assert_equal [@owner.id], response.parsed_body["indicator_assignees"].map { |user| user["id"] }
    assert_no_difference("RoutineIndicatorAssignment.count") { assign([@reader.id]) }
    assert_response :forbidden
    assert_equal [@owner.id], @indicator.reload.user_ids
  end

  test "invisible plans cannot have assignees changed" do
    @plan.update!(sector: :hr, public: false)
    @template.update!(sector: :hr)
    sign_in @reader
    assert_no_difference("RoutineIndicatorAssignment.count") { assign([@reader.id]) }
    assert_response :not_found
  end

  test "invalid user ids leave previous assignees intact" do
    assign([@owner.id])
    [[User.maximum(:id) + 1], [@reader.id, "invalid"], "invalid"].each do |ids|
      assert_no_difference("RoutineIndicatorAssignment.count") { assign(ids) }
      assert_response :unprocessable_entity
      assert_equal [@owner.id], @indicator.reload.user_ids
    end
  end

  test "independent gerots do not offer assignment settings" do
    template = RoutineTemplate.create!(name: "GEROT independente responsáveis", sector: @owner.sector)
    category = template.routine_categories.create!(name: "Categoria", position: 0)
    category.routine_indicators.create!(name: "Indicador", position: 0)
    routine = Routines::Generator.call(template: template, created_by: @owner,
      period_start: Date.new(2026, 10, 1), period_end: Date.new(2026, 10, 2))
    @value = routine.routine_values.first
    get routine_value_routine_comments_path(@value), as: :json
    assert_not response.parsed_body["has_action_plan"]
    assert_not response.parsed_body["can_manage_assignees"]
    assign([@owner.id])
    assert_response :forbidden
  end

  private

  def generate(date)
    Routines::Generator.call(template: @template, action_plan: @plan, created_by: @owner,
      period_start: date, period_end: date + 1.day)
  end

  def assign(ids)
    patch routine_value_indicator_assignees_path(@value), params: { routine_indicator: { user_ids: ids } }, as: :json
  end

  def comment_task(body)
    assert_difference("Task.count", 1) do
      post routine_value_routine_comments_path(@value), params: { routine_comment: { body: body } }, as: :json
    end
    assert_response :created
    Task.find(response.parsed_body.fetch("generated_task_id"))
  end
end
