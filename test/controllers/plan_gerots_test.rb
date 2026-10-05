require "test_helper"
require "minitest/mock"

class PlanGerotsTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper
  setup do
    @user = users(:one)
    @user.update!(name: "Gestor", role: :admin)
    @plan = @user.action_plans.create!(name: "Produção 2026", sector: @user.sector)
    bucket = @plan.buckets.create!(name: "Qualidade", position: 3)
    @template = Routines::PlanTemplateBuilder.call(action_plan: @plan, attributes: { name: "GEROT Produção" })
    @category = @template.routine_categories.find_by!(bucket: bucket)
    @indicator = @category.routine_indicators.create!(
      name: "Refugo", position: 0, calculation_type: :ranged,
      value_type: :decimal, goal_direction: :less_or_equal
    )
    @indicator.routine_indicator_targets.create!(goal: "5", starts_at: Date.new(2026, 1, 1))
  end

  test "annual tab displays twelve months and links to period generation" do
    get action_plan_path(@plan, view: "gerots", year: 2026)

    assert_response :success
    assert_select ".plan-gerots__month", count: 12
    assert_select "a[href=?]", new_action_plan_gerot_generator_path(@plan, year: 2026, month: 2)
    assert_select ".action-plan-view-switch__link--gerots.active", text: /GEROTs/
  end

  test "generation defaults to the selected month including leap years" do
    get new_action_plan_gerot_generator_path(@plan, year: 2028, month: 2)

    assert_response :success
    assert_select "input[name=period_start][value='2028-02-01']"
    assert_select "input[name=period_end][value='2028-02-29']"
    assert_select "select[name^='category_bucket_ids']", count: 0
    assert_select ".plan-gerot-bucket-field", text: /Qualidade/
    assert_select "input[name=task_generation_mode][value=commented_deviation][checked]"
  end

  test "calendar and generation use the plan year without a year selector" do
    @plan.update!(created_at: Time.zone.local(2024, 3, 1))
    get action_plan_path(@plan, view: "gerots", year: 2031)
    assert_response :success
    assert_select "select[name=year]", count: 0
    assert_select ".plan-gerots h2", count: 0
    assert_select "a[href=?]", new_action_plan_gerot_generator_path(@plan, year: 2024, month: 2)
    get new_action_plan_gerot_generator_path(@plan, month: 2)
    assert_select "input[name=period_start][value='2024-02-01']"
    assert_select "input[name=period_end][value='2024-02-29']"

    first = Routines::Generator.call(template: @template, action_plan: @plan, created_by: @user,
      period_start: Date.new(2025, 11, 1), period_end: Date.new(2025, 11, 30))
    get action_plan_path(@plan, view: "gerots")
    assert_select "a[href=?]", routine_path(first)
    assert_select "a[href=?]", new_action_plan_gerot_generator_path(@plan, year: 2025, month: 2)
    get new_action_plan_gerot_generator_path(@plan, month: 2)
    assert_select "input[name=period_start][value='2025-02-01']"
  end

  test "tasks default to a comment on an out of goal cell and subsequent comments reuse the task" do
    post action_plan_gerot_generator_path(@plan), params: {
      routine_template_id: @template.id, period_start: "2026-01-01", period_end: "2026-01-31"
    }
    routine = Routine.last
    assert routine.task_generation_commented_deviation?
    value = routine.routine_values.first
    assert_no_difference("Task.count") { save_value(value, "8") }
    assert_not response.parsed_body["generated_task_created"]

    get routine_value_routine_comments_path(value), as: :json
    assert_equal "danger", response.parsed_body["cell_status"]
    assert response.parsed_body["can_generate_task"]

    assert_difference(["Task.count", "RoutineComment.count", "Comment.count"], 1) do
      comment_on(value, "Revisar o processo de produção")
    end
    assert_response :created
    task = value.reload.generated_task
    assert response.parsed_body["generated_task_created"]
    assert_equal action_plan_path(@plan, task_id: task.id), response.parsed_body["generated_task_url"]
    assert_includes task.description, "Comentário: Revisar o processo de produção"
    assert_equal "Revisar o processo de produção", task.comments.first.content
    assert_equal @user, task.comments.first.user
    assert_equal "Qualidade", task.bucket.name

    assert_no_difference("Task.count") { save_value(value, "3") }
    assert_not response.parsed_body["generated_task_created"]
    assert_difference("Comment.count", 1) do
      assert_no_difference("Task.count") { comment_on(value, "Processo ajustado; acompanhar amanhã") }
    end
    assert_not response.parsed_body["generated_task_created"]
    assert_equal task.id, response.parsed_body["generated_task_id"]
    assert_not task.reload.completed?
    assert_equal "success", task.task_activities.routine_value_changed.last.metadata["status"]
    assert_equal 2, task.comments.count

    assert_no_difference("Task.count") { delete routine_value_routine_comment_path(value, value.routine_comments.first), as: :json }
    assert_equal 2, task.comments.count
  end

  test "normal blank manual and goal-less indicators never generate a task from comments" do
    create_gerot("2026-01-01", "2026-01-31", task_generation_mode: "commented_deviation")
    value = Routine.last.routine_values.first
    assert_no_difference("Task.count") do
      save_value(value, "3")
      comment_on(value, "Comentário de acompanhamento")
      save_value(value, "")
      comment_on(value, "Aguardando preenchimento")
      @indicator.update!(calculation_type: :manual_calculation)
      save_value(value, "8")
      comment_on(value, "Indicador manual")
      @indicator.update!(calculation_type: :ranged)
      @indicator.routine_indicator_targets.destroy_all
      save_value(value, "9")
      comment_on(value, "Sem meta")
    end
  end

  test "blank comments are rejected without creating a task" do
    create_gerot("2026-01-01", "2026-01-31", task_generation_mode: "commented_deviation")
    value = Routine.last.routine_values.first
    save_value(value, "8")
    assert_no_difference(["Task.count", "RoutineComment.count", "Comment.count"]) { comment_on(value, "  ") }
    assert_response :unprocessable_entity
  end

  test "closed and archived gerots keep comments without generating tasks" do
    create_gerot("2026-01-01", "2026-01-31", task_generation_mode: "commented_deviation")
    routine = Routine.last
    value = routine.routine_values.first
    save_value(value, "8")
    %i[closed archived].each do |status|
      routine.update!(status: status)
      assert_difference("RoutineComment.count", 1) do
        assert_no_difference(["Task.count", "Comment.count"]) { comment_on(value, "Registro após encerramento") }
      end
      assert_response :created
    end
  end

  test "task generation can be changed per gerot without creating tasks retroactively" do
    create_gerot("2026-01-01", "2026-01-31", task_generation_mode: "commented_deviation")
    routine = Routine.last
    value = routine.routine_values.first
    save_value(value, "8")
    assert_no_difference("Task.count") do
      patch routine_generator_path(routine), params: { task_generation_mode: "deviation", indicator_ids: [@indicator.id] }
    end
    assert_redirected_to routine
    assert routine.reload.task_generation_deviation?
    assert_difference("Task.count", 1) { save_value(value, "9") }
    assert_no_difference("Task.count") { comment_on(value, "Investigar a causa") }
    assert_equal "Investigar a causa", value.reload.generated_task.comments.first.content
  end

  test "tasks tab restores the responsive default view" do
    get action_plan_path(@plan, view: "gerots")
    assert_select ".action-plan-view-switch__link--kanban[href=?]", action_plan_path(@plan, view: "kanban"), text: /Kanban/
    get action_plan_path(@plan)
    assert_select ".action-plan-show--auto-view .action-plan-auto-kanban"
    assert_select ".action-plan-show--auto-view .action-plan-auto-list"
  end

  test "gerot actions use responsive kanban and keep period and completed task filters" do
    create_gerot("2026-01-01", "2026-01-31")
    january = Routine.last
    january_values = january.routine_values.order(:reference_date).first(2)
    january_values.each { |value| save_value(value, "8") }
    open_task, done_task = january_values.map { |value| value.reload.generated_task }
    done_task.update!(completed: true)
    create_gerot("2026-02-01", "2026-02-28")
    february = Routine.last
    save_value(february.routine_values.first, "8")
    february_task = february.routine_values.first.generated_task
    ordinary_task = open_task.bucket.tasks.create!(creator: @user, title: "Ação independente", completed: true)

    get action_plan_path(@plan, view: "gerot_actions", routine_id: january.id)
    assert_response :success
    assert_select ".action-plan-show--auto-view .action-plan-auto-kanban"
    assert_select ".action-plan-auto-list [data-task-id='#{open_task.id}']"
    assert_select ".action-plan-auto-kanban [data-task-id='#{open_task.id}']"
    assert_select ".action-plan-auto-kanban #done-tasks-#{open_task.bucket_id} [data-task-id='#{done_task.id}']"
    assert_select "[data-task-id='#{february_task.id}']", count: 0
    assert_select "[data-task-id='#{ordinary_task.id}']", count: 0
    assert_select ".action-plan-auto-kanban [data-toggle-done-preloaded-value=true]"
    assert_select ".action-plan-kanban-card__composer", count: 0

    plan_stream = Turbo::StreamsChannel.send(:stream_name_from, [@plan, :gerot_tasks])
    january_stream = Turbo::StreamsChannel.send(:stream_name_from, [january, :gerot_tasks])
    february_stream = Turbo::StreamsChannel.send(:stream_name_from, [february, :gerot_tasks])
    assert_broadcasts plan_stream, 3 do
      assert_broadcasts january_stream, 3 do
        assert_no_broadcasts february_stream do
          open_task.update!(completed: true)
        end
      end
    end

    get action_plan_bucket_task_path(@plan, open_task.bucket, open_task), params: { view: "gerot_actions", routine_id: january.id }
    assert_select "input[type=hidden][name=view][value=gerot_actions]"
    assert_select "input[type=hidden][name=routine_id][value='#{january.id}']"
    patch toggle_complete_action_plan_bucket_task_path(@plan, open_task.bucket, open_task),
      params: { view: "gerot_actions", routine_id: january.id }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target='done-count-#{open_task.bucket_id}']", text: /Tarefas concluídas \(1\)/
  end

  test "a task generation failure rolls back its triggering comment" do
    create_gerot("2026-01-01", "2026-01-31", task_generation_mode: "commented_deviation")
    value = Routine.last.routine_values.first
    save_value(value, "8")
    TaskActivityService.stub(:log, ->(**) { raise ActiveRecord::RecordInvalid.new(Task.new) }) do
      assert_no_difference(["Task.count", "RoutineComment.count", "Comment.count"]) { comment_on(value, "Revisar o processo") }
    end
    assert_response :unprocessable_entity
  end

  test "creates monthly gerots in the same annual plan and reuses category buckets" do
    create_gerot("2026-01-01", "2026-01-31")
    january = Routine.last
    bucket = @plan.routine_category_buckets.find_by!(routine_category: @category).bucket
    assert_equal @plan, january.action_plan
    assert_equal "Qualidade", bucket.name

    assert_no_difference("Bucket.count") { create_gerot("2026-02-01", "2026-02-28") }
    assert_equal 2, @plan.routines.count
    assert_equal @plan.buckets.count, @plan.routine_category_buckets.count
  end

  test "categories cannot be redirected away from their source bucket" do
    bucket = @plan.buckets.find_by!(name: "A Fazer")
    assert_no_difference("Routine.count") { create_gerot("2026-01-01", "2026-01-31", category_bucket_ids: { @category.id.to_s => bucket.id }) }
    assert_response :unprocessable_entity
    assert_equal @category.bucket, @plan.routine_category_buckets.find_by!(routine_category: @category).bucket
  end

  test "rejects buckets from another plan without creating a gerot" do
    another = @user.action_plans.create!(name: "Outro plano")
    assert_no_difference("Routine.count") do
      create_gerot("2026-01-01", "2026-01-31", category_bucket_ids: { @category.id.to_s => another.buckets.first.id })
    end
    assert_response :unprocessable_entity
  end

  test "duplicate period displays validation and models belong exclusively to their plan" do
    create_gerot("2026-01-01", "2026-01-31")
    assert_no_difference("Routine.count") { create_gerot("2026-01-01", "2026-01-31") }
    assert_response :unprocessable_entity
    assert_select ".alert-danger", text: /já possui um GEROT/

    @plan = @user.action_plans.create!(name: "Outro plano 2026")
    Routines::PlanTemplateBuilder.call(action_plan: @plan)
    assert_no_difference("Routine.count") { create_gerot("2026-01-01", "2026-01-31") }
    assert_response :not_found
  end

  test "invalid periods show an error and preserve the submitted fields" do
    assert_no_difference("Routine.count") { create_gerot("2026-02-28", "2026-02-01") }
    assert_response :unprocessable_entity
    assert_select "input[name=period_start][value='2026-02-28']"

    create_gerot("not-a-date", "2026-02-28")
    assert_response :unprocessable_entity
  end

  test "linking legacy gerots preserves values and does not generate historical tasks" do
    source = independent_template
    legacy = Routines::Generator.call(template: source, period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 1, 31), created_by: @user)
    value = legacy.routine_values.first
    value.update!(value: "8")
    value.routine_comments.create!(user: @user, body: "Investigar causa")

    assert_no_difference(["RoutineValue.count", "Task.count", "RoutineComment.count"]) do
      post action_plan_gerots_path(@plan), params: { routine_id: legacy.id, category_bucket_ids: { source.routine_categories.first.id.to_s => @category.bucket_id } }
    end
    assert_redirected_to action_plan_path(@plan, view: "gerots", year: 2026)
    assert_equal @plan, legacy.reload.action_plan
    assert_equal "8", value.reload.value
    assert_equal "Investigar causa", value.routine_comments.first.body
    assert_equal @template, legacy.routine_template
    assert_equal "Qualidade", value.routine_indicator.routine_category.name
    assert_nil source.reload.action_plan
  end

  test "existing linked gerots cannot be reassigned to another plan" do
    create_gerot("2026-01-01", "2026-01-31")
    routine = Routine.last
    another = @user.action_plans.create!(name: "Outro plano")
    post action_plan_gerots_path(another), params: { routine_id: routine.id }
    assert_equal @plan, routine.reload.action_plan
    assert_empty another.routine_category_buckets
  end

  test "saving a deviation generates one task with provenance and edits never duplicate it" do
    create_gerot("2026-01-01", "2026-01-31")
    routine = Routine.last
    value = routine.routine_values.first

    assert_difference("Task.count", 1) { save_value(value, "8") }
    assert_response :success
    task = value.reload.generated_task
    assert_equal @plan, task.bucket.action_plan
    assert_equal "Qualidade", task.bucket.name
    assert_equal @user, task.creator
    assert_includes task.description, "Meta: menor ou igual a 5"

    assert_no_difference("Task.count") do
      save_value(value, "9")
      save_value(value, "3")
      save_value(value, "8")
    end
    assert_not task.reload.completed?
    correction = task.task_activities.routine_value_changed.find_by!(new_value: "3")
    assert_equal "success", correction.metadata["status"]

    get action_plan_path(@plan, view: "gerot_actions", routine_id: routine.id)
    assert_response :success
    assert_select "[data-task-id='#{task.id}']"

    get action_plan_bucket_task_path(@plan, task.bucket, task)
    assert_response :success
    assert_select "a[href=?]", routine_path(routine), text: /Origem:/
  end

  test "uses the target for the reference date and respects lower and upper limits" do
    @indicator.routine_indicator_targets.create!(goal: "10", starts_at: Date.new(2026, 1, 15))
    create_gerot("2026-01-01", "2026-01-31")
    routine = Routine.last
    early = routine.routine_values.find_by!(reference_date: "2026-01-10")
    later = routine.routine_values.find_by!(reference_date: "2026-01-20")
    assert_difference("Task.count", 1) { save_value(early, "8") }
    assert_no_difference("Task.count") { save_value(later, "8") }

    @indicator.update!(goal_direction: :greater_or_equal)
    assert_difference("Task.count", 1) { save_value(later, "7") }
  end

  test "blank manual and goal-less values do not create corrective tasks" do
    create_gerot("2026-01-01", "2026-01-31")
    value = Routine.last.routine_values.first
    assert_no_difference("Task.count") do
      save_value(value, "3")
      save_value(value, "")
      @indicator.update!(calculation_type: :manual_calculation)
      save_value(value, "8")
      @indicator.update!(calculation_type: :ranged)
      @indicator.routine_indicator_targets.destroy_all
      save_value(value, "9")
    end
  end

  test "closing the month keeps pending tasks and rejects further fills" do
    create_gerot("2026-01-01", "2026-01-31")
    routine = Routine.last
    value = routine.routine_values.first
    save_value(value, "8")
    task = value.reload.generated_task

    patch close_routine_path(routine)
    assert routine.reload.closed?
    assert_not task.reload.completed?
    assert_no_difference("Task.count") { save_value(value, "9") }
    assert_response :unprocessable_entity
    assert_equal "8", value.reload.value
  end

  test "deviation generation keeps the collaborative cell broadcast" do
    create_gerot("2026-01-01", "2026-01-31")
    routine = Routine.last
    stream = Turbo::StreamsChannel.send(:stream_name_from, [routine, :collaboration])
    assert_broadcasts stream, 1 do
      save_value(routine.routine_values.first, "8")
    end
  end

  test "generated tasks can move between buckets only within their source plan" do
    create_gerot("2026-01-01", "2026-01-31")
    value = Routine.last.routine_values.first
    save_value(value, "8")
    task = value.reload.generated_task
    other = @user.action_plans.create!(name: "Outro plano")
    assert_not task.update(bucket: other.buckets.first)
    assert task.update(bucket: @plan.buckets.find_by!(name: "Em Andamento"))
    assert_equal value, task.reload.routine_value
  end

  test "renaming a bucket also renames its category without moving tasks" do
    create_gerot("2026-01-01", "2026-01-31")
    routine = Routine.last
    first, second = routine.routine_values.order(:reference_date).first(2)
    save_value(first, "8")
    original_bucket = first.reload.generated_task.bucket
    patch action_plan_bucket_path(@plan, original_bucket), params: { bucket: { name: "Qualidade da produção" } }
    assert_response :success
    assert_equal "Qualidade da produção", @category.reload.name
    save_value(second, "8")
    assert_equal original_bucket, second.reload.generated_task.bucket
    assert_equal original_bucket, first.reload.generated_task.bucket
  end

  test "deleting a gerot preserves its generated tasks" do
    create_gerot("2026-01-01", "2026-01-31")
    routine = Routine.last
    value = routine.routine_values.first
    save_value(value, "8")
    task = value.reload.generated_task

    delete routine_path(routine)
    assert_nil task.reload.routine_value_id
    assert_includes task.description, routine.title
  end

  test "plans and buckets with gerot links cannot be deleted accidentally" do
    create_gerot("2026-01-01", "2026-01-31")
    value = Routine.last.routine_values.first
    save_value(value, "8")
    bucket = @category.bucket
    assert_no_difference("Bucket.count") { delete action_plan_bucket_path(@plan, bucket) }
    assert_no_difference("ActionPlan.count") { delete action_plan_path(@plan) }
  end

  test "plan templates cannot be used by the independent generator" do
    get new_routine_template_generator_path(@template)
    assert_response :not_found
    sign_in @user
    assert_no_difference("Routine.count") do
      post routine_template_generator_path(@template), params: { period_start: "2026-01-01", period_end: "2026-01-31" }
    end
    assert_response :not_found
  end

  test "readers can see a plan but cannot generate or attach gerots" do
    users(:two).update!(name: "Leitor", role: :user)
    sign_out @user
    sign_in users(:two)
    get action_plan_path(@plan, view: "gerots")
    assert_response :success
    assert_select "a", text: "Gerar GEROT", count: 0
    get new_action_plan_gerot_generator_path(@plan)
    assert_response :forbidden
    assert_no_difference("Routine.count") { create_gerot("2026-01-01", "2026-01-31") }
    assert_response :forbidden
  end

  test "private plan permissions also protect gerot values and comments" do
    users(:two).update!(name: "Leitor", role: :user)
    @plan.update!(public: false, sector: :hr)
    @template.update!(sector: :hr)
    create_gerot("2026-01-01", "2026-01-31")
    routine = Routine.last
    value = routine.routine_values.first
    sign_out @user
    sign_in users(:two)

    get routine_path(routine)
    assert_response :not_found
    sign_in users(:two)
    assert_no_difference("Task.count") { save_value(value, "9") }
    assert_response :not_found
    sign_in users(:two)
    get routine_value_routine_comments_path(value)
    assert_response :not_found
    sign_in users(:two)
    get routine_activities_path(routine)
    assert_response :not_found
  end

  private

  def independent_template
    template = RoutineTemplate.create!(name: "GEROT independente #{SecureRandom.hex(4)}", sector: @user.sector)
    category = template.routine_categories.create!(name: "Qualidade", position: 0)
    indicator = category.routine_indicators.create!(name: "Refugo", position: 0, calculation_type: :ranged, value_type: :decimal, goal_direction: :less_or_equal)
    indicator.routine_indicator_targets.create!(goal: "5", starts_at: Date.new(2026, 1, 1))
    template
  end

  def create_gerot(first, last, **settings)
    post action_plan_gerot_generator_path(@plan), params: {
      routine_template_id: @template.id, period_start: first, period_end: last, task_generation_mode: "deviation"
    }.merge(settings)
  end

  def save_value(value, result)
    patch routine_value_path(value), params: { routine_value: { value: result } }, as: :json
  end

  def comment_on(value, body)
    post routine_value_routine_comments_path(value), params: { routine_comment: { body: body } }, as: :json
  end
end
