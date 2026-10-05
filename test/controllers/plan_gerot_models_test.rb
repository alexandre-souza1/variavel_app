require "test_helper"

class PlanGerotModelsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(name: "Gestor", role: :admin)
    @plan = @user.action_plans.create!(name: "Plano com modelo único", sector: @user.sector)
    @source = RoutineTemplate.create!(name: "Modelo independente para adaptação", sector: @user.sector)
    @category = @source.routine_categories.create!(name: "Qualidade", position: 0)
    @indicator = @category.routine_indicators.create!(name: "Refugo", position: 0, value_type: :decimal, calculation_type: :ranged, goal_direction: :less_or_equal)
    @indicator.routine_indicator_targets.create!(goal: "5", starts_at: Date.new(2026, 1, 1))
  end

  test "plan model is created from buckets with one model per plan" do
    get action_plan_path(@plan, view: "gerots")
    assert_select "a[href=?]", new_action_plan_gerot_template_path(@plan)
    get new_action_plan_gerot_generator_path(@plan)
    assert_redirected_to new_action_plan_gerot_template_path(@plan)
    get new_action_plan_gerot_template_path(@plan)
    assert_response :success
    assert_select "input[name='routine_template[sector]']", count: 0
    assert_difference("RoutineTemplate.count", 1) do
      post action_plan_gerot_template_path(@plan), params: { routine_template: { name: "Modelo do plano", sector: "hr" } }
    end
    model = @plan.reload.gerot_template
    assert_equal @plan.sector, model.sector
    assert_equal @plan.buckets.pluck(:id).sort, model.routine_categories.pluck(:bucket_id).sort
    assert_equal @plan.buckets.pluck(:name), model.routine_categories.pluck(:name)
    assert_no_difference("RoutineTemplate.count") do
      post action_plan_gerot_template_path(@plan), params: { routine_template: { name: "Segundo modelo" } }
    end
    assert_equal "Modelo do plano", model.reload.name
    duplicate = RoutineTemplate.new(name: "Modelo duplicado", action_plan: @plan, sector: @plan.sector)
    assert_not duplicate.valid?
    assert duplicate.errors[:action_plan_id].any?
  end

  test "new buckets renames sorting and empty bucket deletion update model categories" do
    model = Routines::PlanTemplateBuilder.call(action_plan: @plan)
    assert_difference(["Bucket.count", "RoutineCategory.count"], 1) do
      post action_plan_buckets_path(@plan), params: { bucket: { name: "Segurança" }, return_to_gerot_model: "1" }
    end
    assert_redirected_to action_plan_gerot_template_path(@plan)
    bucket = @plan.buckets.find_by!(name: "Segurança")
    category = model.routine_categories.find_by!(bucket: bucket)
    patch action_plan_bucket_path(@plan, bucket), params: { bucket: { name: "Segurança operacional" } }
    assert_equal "Segurança operacional", category.reload.name
    ids = [bucket.id] + @plan.buckets.work.where.not(id: bucket.id).pluck(:id)
    patch sort_buckets_action_plan_path(@plan), params: { bucket_ids: ids }
    assert_response :success
    assert_equal bucket.reload.position, category.reload.position
    assert_difference(["Bucket.count", "RoutineCategory.count", "RoutineCategoryBucket.count"], -1) { delete action_plan_bucket_path(@plan, bucket) }
    assert_equal @plan.buckets.pluck(:id).sort, model.routine_categories.pluck(:bucket_id).sort
  end

  test "model categories cannot be created or edited separately from buckets" do
    model = Routines::PlanTemplateBuilder.call(action_plan: @plan)
    get action_plan_gerot_template_path(@plan)
    assert_response :success
    assert_select ".plan-gerot-new-bucket"
    category = model.routine_categories.first
    assert_select "a[href=?]", edit_routine_template_routine_category_path(model, category), count: 0
    assert_select "form[action=?]", routine_template_routine_category_path(model, category), count: 0
    assert_no_difference("RoutineCategory.count") do
      post routine_template_routine_categories_path(model), params: { routine_category: { name: "Categoria avulsa", position: 0 } }
    end
    assert_response :forbidden
  end

  test "buckets sharing a name still have separate categories and independent names remain unique" do
    @plan.buckets.create!(name: "A Fazer", position: @plan.buckets.count)
    model = Routines::PlanTemplateBuilder.call(action_plan: @plan)
    assert_equal 2, model.routine_categories.where(name: "A Fazer").count
    bucket = @plan.buckets.create!(name: "Segurança", position: @plan.buckets.count)
    bucket.update!(name: "A Fazer")
    assert_equal 3, model.routine_categories.where(name: "A Fazer").count
    assert_equal @plan.buckets.pluck(:id).sort, model.routine_categories.pluck(:bucket_id).sort
    duplicate = @source.routine_categories.build(name: @category.name, position: 1)
    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?
  end

  test "central catalog contains independent models and independent gerots need no plan" do
    model = Routines::PlanTemplateBuilder.call(action_plan: @plan)
    get routine_templates_path
    assert_select ".template-card a[href=?]", routine_template_path(@source)
    assert_select ".template-card a[href=?]", routine_template_path(model), count: 0
    get new_routine_template_generator_path(@source)
    assert_response :success
    assert_select "input[type=date][name=period_start]"
    assert_select ".plan-gerot-task-settings", count: 0
    assert_difference("Routine.count", 1) do
      post routine_template_generator_path(@source), params: { period_start: "2026-01-01", period_end: "2026-01-31" }
    end
    routine = Routine.last
    assert_nil routine.action_plan_id
    assert_equal @source, routine.routine_template
    value = routine.routine_values.first
    assert_no_difference("Task.count") do
      patch routine_value_path(value), params: { routine_value: { value: "8" } }, as: :json
      post routine_value_routine_comments_path(value), params: { routine_comment: { body: "Registrar desvio independente" } }, as: :json
    end
    assert_response :created
  end

  test "link preparation is read only and posting without adaptation opens the page" do
    routine = independent_routine
    assert_no_difference(["RoutineTemplate.count", "Bucket.count", "RoutineCategory.count"]) do
      get new_action_plan_gerot_path(@plan, routine_id: routine.id)
    end
    assert_response :success
    assert_select "select[name='category_bucket_ids[#{@category.id}]']"
    assert_select ".plan-gerot-adaptation__source", text: /Qualidade/
    assert_nil routine.reload.action_plan_id
    post action_plan_gerots_path(@plan), params: { routine_id: routine.id }
    assert_redirected_to new_action_plan_gerot_path(@plan, routine_id: routine.id)
    assert_nil routine.reload.action_plan_id
  end

  test "adaptation preserves cell identity values comments activities targets and other independent gerots" do
    routine = independent_routine
    other = independent_routine(month: 2)
    value = routine.routine_values.first
    value.update!(value: "8", updated_by: @user)
    comment = value.routine_comments.create!(user: @user, body: "Revisar processo")
    activity = routine.routine_activities.create!(user: @user, routine_value: value, activity_type: :value_changed, previous_value: "3", new_value: "8")
    destination = @plan.buckets.find_by!(name: "A Fazer")
    assert_no_difference(["RoutineValue.count", "RoutineComment.count", "RoutineActivity.count", "Task.count"]) do
      connect(routine, @category.id.to_s => destination.id)
    end
    assert_redirected_to action_plan_path(@plan, view: "gerots", year: 2026)
    assert_equal @plan, routine.reload.action_plan
    assert_equal @plan.reload.gerot_template, routine.routine_template
    assert_equal value.id, value.reload.id
    assert_equal "8", value.value
    assert_equal comment, value.routine_comments.first
    assert_equal activity, value.routine_activities.first
    copy = value.routine_indicator
    assert_not_equal @indicator.id, copy.id
    assert_equal @indicator, copy.source_indicator
    assert_equal destination, copy.routine_category.bucket
    assert_equal "5", copy.target_for(value.reference_date).goal
    assert_equal [copy.id], routine.selected_indicator_ids
    assert_equal @source, other.reload.routine_template
    assert_nil other.action_plan_id
    assert_equal @indicator, other.routine_values.first.routine_indicator
    assert_no_difference("RoutineIndicator.count") { connect(other, @category.id.to_s => destination.id) }
    assert_equal copy, other.reload.routine_values.first.routine_indicator
  end

  test "multiple categories can be grouped in one existing bucket" do
    second = @source.routine_categories.create!(name: "Segurança", position: 1)
    safety = second.routine_indicators.create!(name: "Acidentes", position: 0, calculation_type: :plus, value_type: :integer)
    routine = independent_routine
    bucket = @plan.buckets.find_by!(name: "A Fazer")
    connect(routine, @category.id.to_s => bucket.id, second.id.to_s => bucket.id)
    assert_response :redirect
    categories = routine.reload.selected_indicators.map(&:routine_category).uniq
    assert_equal 1, categories.size
    assert_equal bucket, categories.first.bucket
    assert_equal [@indicator.id, safety.id].sort, categories.first.routine_indicators.pluck(:source_indicator_id).sort
  end

  test "adapting a previously linked gerot preserves existing tasks and their history" do
    routine = independent_routine
    routine.update_column(:action_plan_id, @plan.id)
    value = routine.routine_values.first
    bucket = @plan.buckets.find_by!(name: "A Fazer")
    task = bucket.tasks.create!(title: "Ação existente", creator: @user, routine_value: value)
    comment = task.comments.create!(content: "Histórico da ação", user: @user)
    assert_no_difference(["Task.count", "Comment.count", "RoutineValue.count"]) do
      Routines::PlanLinker.call(routine: routine, action_plan: @plan, bucket_ids: { @category.id.to_s => bucket.id })
    end
    assert_equal @plan.reload.gerot_template, routine.reload.routine_template
    assert_equal task, value.reload.generated_task
    assert_equal value, task.reload.routine_value
    assert_equal bucket, task.bucket
    assert_equal comment, task.comments.first
  end

  test "a gerot without categories can be adapted after reviewing the page" do
    empty = RoutineTemplate.create!(name: "Modelo independente vazio", sector: @plan.sector)
    routine = Routines::Generator.call(template: empty, created_by: @user, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
    get new_action_plan_gerot_path(@plan, routine_id: routine.id)
    assert_response :success
    post action_plan_gerots_path(@plan), params: { routine_id: routine.id, adaptation_reviewed: "1" }
    assert_response :redirect
    assert_equal @plan.reload.gerot_template, routine.reload.routine_template
    assert_equal @plan, routine.action_plan
  end

  test "adaptation can create a bucket and preserves legacy goal formats" do
    @indicator.routine_indicator_targets.first.update_column(:goal, "5,0")
    routine = independent_routine
    connect(routine, @category.id.to_s => "new")
    assert_response :redirect
    category = routine.reload.routine_values.first.routine_indicator.routine_category
    assert_equal "Qualidade", category.bucket.name
    assert_equal "5,0", category.routine_indicators.first.routine_indicator_targets.first.goal
  end

  test "missing and foreign bucket mappings cannot partially connect a gerot" do
    routine = independent_routine
    assert_no_difference(["RoutineTemplate.count", "RoutineIndicator.count", "Bucket.count"]) { connect(routine, @category.id.to_s => "") }
    assert_response :unprocessable_entity
    assert_nil routine.reload.action_plan_id
    other = @user.action_plans.create!(name: "Outro plano")
    assert_no_difference(["RoutineTemplate.count", "RoutineIndicator.count", "Bucket.count"]) { connect(routine, @category.id.to_s => other.buckets.first.id) }
    assert_response :not_found
    assert_nil routine.reload.action_plan_id
  end

  test "an overlapping period rolls back the adaptation" do
    first = independent_routine
    destination = @plan.buckets.find_by!(name: "A Fazer")
    connect(first, @category.id.to_s => destination.id)
    other_source = RoutineTemplate.create!(name: "Outro modelo independente", sector: @plan.sector)
    category = other_source.routine_categories.create!(name: "Outra categoria", position: 0)
    category.routine_indicators.create!(name: "Outro KPI", position: 0)
    second = Routines::Generator.call(template: other_source, created_by: @user, period_start: first.period_start, period_end: first.period_end)
    assert_no_difference(["RoutineIndicator.count", "Bucket.count"]) { connect(second, category.id.to_s => "new") }
    assert_response :unprocessable_entity
    assert_nil second.reload.action_plan_id
    assert_equal other_source, second.routine_template
  end

  test "readers can view the model but cannot change indicators or connect gerots" do
    model = Routines::PlanTemplateBuilder.call(action_plan: @plan)
    reader = users(:two)
    reader.update!(name: "Leitor", role: :user)
    sign_in reader
    get action_plan_gerot_template_path(@plan)
    assert_response :success
    assert_select ".plan-gerot-new-bucket", count: 0
    get edit_action_plan_gerot_template_path(@plan)
    assert_response :forbidden
    category = model.routine_categories.first
    assert_no_difference("RoutineIndicator.count") do
      post routine_template_routine_category_routine_indicators_path(model, category), params: { routine_indicator: { name: "KPI proibido" } }
    end
    assert_response :forbidden
    get new_action_plan_gerot_path(@plan)
    assert_response :forbidden
  end

  private

  def independent_routine(month: 1)
    first = Date.new(2026, month, 1)
    Routines::Generator.call(template: @source, created_by: @user, period_start: first, period_end: first.end_of_month)
  end

  def connect(routine, mappings)
    post action_plan_gerots_path(@plan), params: { routine_id: routine.id, category_bucket_ids: mappings }
  end
end
