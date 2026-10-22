require 'test_helper'

class ChecklistTracking::RegisterTaskJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @bucket = tasks(:one).bucket
    @person = Employee.create!(nome: 'ALEXANDRE LOPEZ', matricula: 'LIVE-CHECKLIST-01')
    @person.change_role!({ sector: 'du', cargo: 'motorista', promax: 'LIVE-CHECKLIST-01', starts_on: '2026-01-01', reason: 'Admissão' }, user: @user)
    @title = 'Aplicar matriz ao motorista ALEXANDRE LOPEZ por não realização do Checklist de Retorno no dia 14/03/2026'
    clear_enqueued_jobs
  end

  test 'saving a checklist task queues automatic registration and creates one auditable occurrence' do
    assert_difference('ChecklistOccurrence.count', 1) do
      perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) { @task = @bucket.tasks.create!(title: @title, creator: @user) }
    end
    record = @task.checklist_occurrences.last
    assert_equal @person, record.employee
    assert_equal Date.new(2026, 3, 14), record.occurred_on
    assert_equal 'retorno', record.checklist_kind
    assert_equal 'automatic_name', @task.task_activities.last.metadata['identification_method']
    assert_equal 1, ChecklistTracking::Report.new(scope: ChecklistOccurrence.all, year: 2026).total
    assert_no_difference(['ChecklistOccurrence.count', 'TaskActivity.count']) do
      2.times { ChecklistTracking::RegisterTaskJob.perform_now(@task.id) }
    end
  end

  test 'missing and ambiguous details stay pending and adding the explicit report in comments retries automatically' do
    perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) { @task = @bucket.tasks.create!(title: 'Investigar checklist', creator: @user) }
    assert_empty @task.checklist_occurrences
    assert_difference('ChecklistOccurrence.count', 1) do
      perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) { @task.comments.create!(user: @user, content: @title) }
    end
    assert_equal @person.id, @task.checklist_occurrences.last.employee_id
  end

  test 'completing the task title triggers recognition but another due date is not an occurrence date' do
    @task = @bucket.tasks.create!(title: 'Verificar checklist', creator: @user, due_at: '2026-03-14')
    perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) { @task.update!(title: @title.sub(' no dia 14/03/2026', '')) }
    assert_empty @task.checklist_occurrences
    assert_difference('ChecklistOccurrence.count', 1) do
      perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) { @task.update!(title: @title) }
    end
  end

  test 'GEROT employee and SPOT tasks are recognized automatically after generation commits' do
    template = Routines::PlanTemplateBuilder.call(action_plan: @bucket.action_plan, attributes: { name: 'GEROT automático' })
    category = template.routine_categories.find_by!(bucket: @bucket)
    indicators = ['% Aderência Retorno Rota', '% Aderência SPOT'].map.with_index do |name, position|
      indicator = category.routine_indicators.create!(name: name, position: position, calculation_type: :ranged, value_type: :percentage, goal_direction: :greater_or_equal)
      indicator.routine_indicator_targets.create!(goal: '100', starts_at: '2026-01-01')
      indicator
    end
    routine = Routines::Generator.call(template: template, action_plan: @bucket.action_plan, created_by: @user,
      period_start: Date.new(2026, 3, 14), period_end: Date.new(2026, 3, 14))
    tasks = []
    assert_difference('ChecklistOccurrence.count', 2) do
      perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) do
        indicators.zip(['ALEXANDRE LOPEZ', 'DLL4A97']).each do |indicator, name|
          value = routine.routine_values.find_by!(routine_indicator: indicator)
          value.update!(value: '80')
          comment = value.routine_comments.create!(user: @user, body: name)
          tasks << Routines::DeviationTaskGenerator.call(routine_value: value, actor: @user, comment: comment)
        end
      end
    end
    assert_equal @person.id, tasks.first.checklist_occurrences.last.employee_id
    spot = tasks.last.checklist_occurrences.last
    assert_equal 'DLL4A97', spot.spot_plate
    assert_equal 'saida', spot.checklist_kind
    assert_equal Date.new(2026, 3, 14), spot.occurred_on
  end

  test 'adding an AZ badge resolves a homonym without guessing before the badge exists' do
    operator = Employee.create!(nome: @person.nome, matricula: 'LIVE-CHECKLIST-AZ')
    operator.change_role!({ sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-01-01', reason: 'Admissão' }, user: @user)
    perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) do
      @task = @bucket.tasks.create!(title: 'Aplicar matriz ao colaborador ALEXANDRE LOPEZ por não realização do Checklist no dia 14/03/2026', creator: @user)
    end
    assert_empty @task.checklist_occurrences
    label = @bucket.action_plan.labels.create!(name: 'AZ', color: '#112233')
    assert_difference('ChecklistOccurrence.count', 1) do
      perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) { @task.labels << label }
    end
    assert_equal operator.id, @task.checklist_occurrences.last.employee_id
    assert_equal 'empilhadeira', @task.checklist_occurrences.last.checklist_kind
  end

  test 'existing manual records and exclusions are never overwritten or reactivated' do
    @task = @bucket.tasks.create!(title: @title, creator: @user)
    record = @task.checklist_occurrences.create!(employee: @person, occurred_on: '2026-03-14', checklist_kind: 'saida', recorded_by: @user)
    record.update!(cancelled_at: Time.current, cancelled_by: @user, cancellation_reason: 'Erro de rede')
    assert_no_difference(['ChecklistOccurrence.count', 'TaskActivity.count']) do
      perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) { @task.comments.create!(user: @user, content: @title) }
      ChecklistTracking::RegisterTaskJob.perform_now(@task.id)
    end
    assert record.reload.cancelled_at?
    assert_equal 'saida', record.checklist_kind
  end

  test 'duplicate automatic tasks count one absence and new sources inherit an existing justification' do
    perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) do
      @task = @bucket.tasks.create!(title: @title, creator: @user)
      @bucket.tasks.create!(title: @title, creator: @user)
    end
    assert_equal 2, ChecklistOccurrence.count
    assert_equal 1, ChecklistTracking::Report.new(scope: ChecklistOccurrence.all, year: 2026).total
    ChecklistTracking::Exclusion.new(occurrence: @task.checklist_occurrences.first, user: @user, reason: 'network_error', details: 'Sem sinal').call
    perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) { @bucket.tasks.create!(title: @title, creator: @user) }
    assert_equal 3, ChecklistOccurrence.count
    assert ChecklistOccurrence.order(:id).last.cancelled_at?
    assert_equal 0, ChecklistTracking::Report.new(scope: ChecklistOccurrence.all, year: 2026).total
  end

  test 'DU helpers and people outside the creator scope never become automatic absences' do
    @person.employee_roles.first.update!(cargo: 'ajudante')
    perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) { @bucket.tasks.create!(title: @title, creator: @user) }
    assert_equal 0, ChecklistOccurrence.count
    @person.employee_roles.first.update!(cargo: 'motorista')
    @user.update!(role: :user, sector: :warehouse)
    perform_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) { @bucket.tasks.create!(title: @title, creator: @user) }
    assert_equal 0, ChecklistOccurrence.count
  end

  test 'unrelated tasks inbox tasks and rolled back tasks never generate occurrences' do
    assert_no_enqueued_jobs(only: ChecklistTracking::RegisterTaskJob) do
      @bucket.tasks.create!(title: 'Cobrar produtividade de ALEXANDRE LOPEZ', creator: @user)
      @user.personal_inbox!.tasks.create!(title: @title, creator: @user)
      Task.transaction do
        @bucket.tasks.create!(title: @title, creator: @user)
        raise ActiveRecord::Rollback
      end
    end
    assert_equal 0, ChecklistOccurrence.count
    assert_nothing_raised { ChecklistTracking::RegisterTaskJob.perform_now(-1) }
  end
end
