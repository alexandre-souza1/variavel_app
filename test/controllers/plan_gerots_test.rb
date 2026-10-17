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

  test "each comment on an out of goal cell creates its own investigation task" do
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

    commenter = users(:two)
    commenter.update!(name: "Analista", role: :admin)
    sign_in commenter
    assert_difference(["Task.count", "RoutineComment.count", "Comment.count"], 1) do
      comment_on(value, "Revisar o processo de produção")
    end
    assert_response :created
    task = value.reload.generated_tasks.first
    assert response.parsed_body["generated_task_created"]
    assert_equal action_plan_path(@plan, task_id: task.id), response.parsed_body["generated_task_url"]
    assert_equal "Investigar Refugo fora da meta — Revisar o processo de produção", task.title
    assert_includes task.description, "Comentário: Revisar o processo de produção"
    assert_equal "Revisar o processo de produção", task.comments.first.content
    assert_equal commenter, task.comments.first.user
    assert_equal [commenter.id], task.user_ids
    assert_equal "Qualidade", task.bucket.name

    sign_in @user
    assert_difference(["Task.count", "RoutineComment.count", "Comment.count"], 1) do
      comment_on(value, "Verificar a matéria-prima")
    end
    assert_response :created
    second_task = Task.find(response.parsed_body["generated_task_id"])
    assert response.parsed_body["generated_task_created"]
    assert_not_equal task.id, second_task.id
    assert_equal action_plan_path(@plan, task_id: second_task.id), response.parsed_body["generated_task_url"]
    assert_equal "Investigar Refugo fora da meta — Verificar a matéria-prima", second_task.title
    assert_includes second_task.description, "Comentário: Verificar a matéria-prima"
    assert_equal ["Verificar a matéria-prima"], second_task.comments.pluck(:content)
    assert_equal [@user.id], second_task.user_ids
    assert_equal task.bucket, second_task.bucket
    assert_equal value.routine_comments.last, second_task.routine_comment
    assert_equal ["Revisar o processo de produção"], task.comments.pluck(:content)
    assert_equal 2, value.generated_tasks.count

    get action_plan_path(@plan, view: "gerot_actions", routine_id: routine.id)
    assert_response :success
    [task, second_task].each { |action| assert_select "[data-task-id='#{action.id}']" }

    assert_no_difference("Task.count") { save_value(value, "3") }
    assert_not response.parsed_body["generated_task_created"]
    [task, second_task].each do |action|
      assert_not action.reload.completed?
      assert_equal "success", action.task_activities.routine_value_changed.last.metadata["status"]
    end
    assert_no_difference(["Task.count", "Comment.count"]) do
      comment_on(value, "Processo ajustado; acompanhar amanhã")
    end
    assert_nil response.parsed_body["generated_task_id"]

    assert_no_difference("Task.count") do
      delete routine_value_routine_comment_path(value, task.routine_comment), as: :json
    end
    assert_nil task.reload.routine_comment_id
    assert_equal value, task.routine_value
    assert_equal ["Revisar o processo de produção"], task.comments.pluck(:content)
  end

  test "retrying generation for the same comment does not duplicate its task" do
    create_gerot("2026-01-01", "2026-01-31", task_generation_mode: "commented_deviation")
    value = Routine.last.routine_values.first
    save_value(value, "8")
    comment_on(value, "Investigar a causa")
    task = Task.find(response.parsed_body["generated_task_id"])

    assert_no_difference(["Task.count", "Comment.count", "TaskActivity.count"]) do
      generated = Routines::DeviationTaskGenerator.call(
        routine_value: value, actor: @user, comment: task.routine_comment
      )
      assert_equal task, generated
    end
  end

  test "tasks generated from a deviation comment inherit all indicator labels at creation" do
    labels = [
      @plan.labels.create!(name: "Segurança", color: "#ff6600"),
      @plan.labels.create!(name: "Frota", color: "#3366ff")
    ]
    @indicator.update!(labels: labels)
    create_gerot("2026-01-01", "2026-01-31", task_generation_mode: "commented_deviation")
    value = Routine.last.routine_values.first
    assert_no_difference(["Task.count", "TaskLabel.count"]) { save_value(value, "8") }

    assert_difference("Task.count", 1) do
      assert_difference("TaskLabel.count", 2) { comment_on(value, "Verificar a conformidade") }
    end
    assert_response :created
    task = value.reload.generated_tasks.first
    assert_equal labels.map(&:id).sort, task.label_ids.sort
    assert_equal @plan.id, task.bucket.action_plan_id

    manual_label = @plan.labels.create!(name: "Acompanhamento", color: "#228833")
    task.update!(labels: [labels.first, manual_label])
    @indicator.update!(labels: [labels.last])
    assert_difference(["Task.count", "TaskLabel.count"], 1) { comment_on(value, "Acompanhando a correção") }
    assert_response :created
    second_task = Task.find(response.parsed_body["generated_task_id"])
    assert_not_equal task.id, second_task.id
    assert_equal [labels.last.id], second_task.label_ids
    assert_equal [labels.first.id, manual_label.id].sort, task.reload.label_ids.sort
  end

  test "tasks generated on value entry also inherit indicator labels" do
    label = @plan.labels.create!(name: "Qualidade", color: "#228833")
    @indicator.update!(labels: [label])
    create_gerot("2026-01-01", "2026-01-31", task_generation_mode: "deviation")
    value = Routine.last.routine_values.first

    assert_difference(["Task.count", "TaskLabel.count"], 1) { save_value(value, "8") }
    assert_response :success
    assert_equal [label.id], value.reload.generated_tasks.first.label_ids
    assert_empty value.generated_tasks.first.user_ids
    assert_equal "Investigar Refugo fora da meta — #{value.reference_date.strftime('%d/%m/%Y')}", value.generated_tasks.first.title
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
    initial_task = value.generated_tasks.first
    assert_difference("Task.count", 1) { comment_on(value, "Investigar a causa") }
    comment_task = Task.find(response.parsed_body["generated_task_id"])
    assert_not_equal initial_task.id, comment_task.id
    assert_equal "Investigar a causa", comment_task.comments.first.content
    assert_empty initial_task.comments
    assert_no_difference("Task.count") { save_value(value, "10") }
    assert_equal 2, value.generated_tasks.count
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
    open_task, done_task = january_values.map { |value| value.reload.generated_tasks.first }
    done_task.update!(completed: true)
    create_gerot("2026-02-01", "2026-02-28")
    february = Routine.last
    save_value(february.routine_values.first, "8")
    february_task = february.routine_values.first.generated_tasks.first
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
    label = @plan.labels.create!(name: "Segurança", color: "#ff6600")
    @indicator.update!(labels: [label])
    create_gerot("2026-01-01", "2026-01-31", task_generation_mode: "commented_deviation")
    value = Routine.last.routine_values.first
    save_value(value, "8")
    TaskActivityService.stub(:log, ->(**) { raise ActiveRecord::RecordInvalid.new(Task.new) }) do
      assert_no_difference(["Task.count", "TaskLabel.count", "RoutineComment.count", "Comment.count"]) { comment_on(value, "Revisar o processo") }
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
    task = value.reload.generated_tasks.first
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
    task = value.reload.generated_tasks.first

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
    task = value.reload.generated_tasks.first
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
    original_bucket = first.reload.generated_tasks.first.bucket
    patch action_plan_bucket_path(@plan, original_bucket), params: { bucket: { name: "Qualidade da produção" } }
    assert_response :success
    assert_equal "Qualidade da produção", @category.reload.name
    save_value(second, "8")
    assert_equal original_bucket, second.reload.generated_tasks.first.bucket
    assert_equal original_bucket, first.reload.generated_tasks.first.bucket
  end

  test "deleting a gerot preserves its generated tasks" do
    create_gerot("2026-01-01", "2026-01-31")
    routine = Routine.last
    value = routine.routine_values.first
    save_value(value, "8")
    task = value.reload.generated_tasks.first
    comment_on(value, "Falha no processo")
    comment_task = Task.find(response.parsed_body["generated_task_id"])

    assert_no_difference("Task.count") { delete routine_path(routine) }
    [task, comment_task].each do |action|
      assert_nil action.reload.routine_value_id
      assert_nil action.routine_comment_id
      assert_includes action.description, routine.title
    end
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
