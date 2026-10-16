require "test_helper"
require "minitest/mock"
require_relative "../support/automation_setup"

class AutomationsTest < ActiveSupport::TestCase
  include AutomationSetup
  setup { setup_automation_data }
  teardown { travel_back }

  test "preview reads scoped financial data without any business or history writes" do
    create_automation_expense("100.25")
    create_automation_expense("50.50")
    create_automation_expense(900, date: 1.month.ago.to_date)
    rule = finance_rule
    assert_no_difference ["RoutineValue.count", "AutomationRule.count", "AutomationRun.count", "Task.count", "Notification.count", "Bucket.count"] do
      preview = Automations::Preview.call(rule)
      assert_equal BigDecimal("150.75"), preview[:result][:value]
      assert_equal 2, preview[:result][:count]
      assert_equal Date.current.end_of_month, preview[:destination][:reference_date]
    end
  end

  test "execution replaces values without adding totals again and preserves GEROT audit" do
    rule = finance_rule
    create_automation_expense(100)
    run = run_automation(rule)
    assert_equal "success", run.status
    target = @routine.routine_values.find_by!(routine_indicator: @indicator)
    assert_equal "100.0", target.value
    assert_equal rule.id, target.automation_rule_id
    assert_equal "automation", @routine.routine_activities.last.metadata["source"]
    assert_no_difference "RoutineActivity.count" do
      assert_equal "unchanged", run_automation(rule).status
    end
    create_automation_expense(30)
    assert_equal "success", run_automation(rule).status
    assert_equal "130.0", target.reload.value
    assert_equal 1, @routine.routine_values.count
  end

  test "manual values and other automation values are protected" do
    create_automation_expense(100)
    rule = finance_rule
    target = @routine.routine_values.create!(routine_indicator: @indicator, reference_date: Date.current.end_of_month, value: "75")
    assert_equal "skipped", run_automation(rule).status
    assert_equal "75", target.reload.value
    rule.update!(action_config: rule.action_config.merge("overwrite_manual" => "1"))
    assert_equal "success", run_automation(rule).status
    second = finance_rule(name: "Outra regra", action_config: rule.action_config)
    assert_equal "skipped", run_automation(second).status
    assert_equal rule.id, target.reload.automation_rule_id
  end

  test "no financial rows preserves existing automation values instead of writing zero" do
    rule = finance_rule
    invoice = create_automation_expense(100)
    run_automation(rule)
    invoice.destroy!
    assert_equal "skipped", run_automation(rule).status
    assert_equal "100.0", @routine.routine_values.first.value
  end

  test "closed ambiguous or unselected GEROT destinations are skipped" do
    rule = finance_rule
    create_automation_expense(100)
    @routine.closed!
    assert_equal "skipped", run_automation(rule).status
    @routine.open!
    @template.routines.create!(created_by: @owner, title: "Sobreposição", period_start: Date.current, period_end: Date.current.end_of_month)
    assert_match(/sobrepostos/, run_automation(rule).message)
  end

  test "frequency and output type must match the selected destination" do
    rule = finance_rule(period: "today")
    refute rule.valid?
    assert_match(/frequência/, rule.errors.full_messages.to_sentence)
    rule.period = "month"
    @indicator.update!(value_type: :integer)
    refute rule.valid?
    assert_match(/moeda/, rule.errors.full_messages.to_sentence)
  end

  test "owner permissions are rechecked at every execution even when admin initiates it" do
    rule = finance_rule
    create_automation_expense(100)
    rule.save!
    admin = users(:two)
    admin.update!(role: :admin)
    @owner.update!(sector: :hr)
    run = Automations::Runner.call(rule, actor: admin)
    assert_equal "skipped", run.status
    assert_empty @routine.routine_values
    @owner.update!(active: false)
    assert_equal "skipped", Automations::Runner.call(rule, actor: admin).status
  end

  test "financial category and sector filters cannot cross permissions" do
    other = BudgetCategory.create!(name: "RH teste", sector: :rh)
    rule = finance_rule(filters: { "budget_category_id" => other.id.to_s })
    refute rule.valid?
    rule.filters = { sector: "rh" }
    refute rule.valid?
    rule.filters = {}
    create_automation_expense(100)
    hr = users(:two)
    hr.update!(sector: :hr)
    create_automation_expense(900, purchaser: hr, category: other)
    assert_equal BigDecimal("100"), Automations::Preview.call(rule)[:result][:value]
  end

  test "conditions gate notifications and repeated execution sends only one per period" do
    rule = task_rule(condition_operator: "gt", condition_value: 0)
    assert_no_difference "Notification.count" do
      assert_equal "skipped", run_automation(rule).status
    end
    @plan.buckets.first.tasks.create!(creator: @owner, title: "Revisar pneus", due_at: 1.hour.from_now)
    assert_difference "Notification.count", 1 do
      run = run_automation(rule)
      assert_equal "success", run.status
      assert_match(/1 pendências/, Notification.last.title)
      assert_equal @owner.id, Notification.last.user_id
    end
    assert_no_difference "Notification.count" do
      assert_equal "unchanged", run_automation(rule).status
    end
    travel 1.day
    assert_equal "skipped", run_automation(rule).status
  end

  test "tasks are created once per period in a permitted bucket with interpolated text" do
    rule = task_rule(action_key: "create_task", action_config: { title: "Revisar {{valor}} pendências", due_in_days: "2" })
    assert_difference "Task.count", 1 do
      assert_equal "success", run_automation(rule).status
    end
    task = Task.last
    assert task.inbox?
    assert_equal @owner, task.creator
    assert_equal [@owner.id], task.user_ids
    assert_equal Date.current + 2, task.due_at.to_date
    assert_match(/Automação: Pendências/, task.description)
    assert_no_difference "Task.count" do
      assert_equal "unchanged", run_automation(rule).status
    end
    travel 1.day
    assert_difference "Task.count", 1 do
      assert_equal "success", run_automation(rule).status
    end
  end

  test "all-history rules do not repeat their action as the date advances" do
    rule = task_rule(period: "all")
    assert_equal "success", run_automation(rule).status
    travel 2.days
    assert_equal "unchanged", run_automation(rule).status
  end

  test "private tasks and inaccessible destinations never enter another users rules" do
    other = users(:two)
    Task.create!(title: "Privada", creator: other, bucket: other.personal_inbox!, due_at: 1.hour.from_now)
    rule = task_rule(filters: { status: "pending" })
    expected = Task.accessible_to(@owner).where(completed: [false, nil], due_at: Date.current.all_day).count
    assert_equal expected, Automations::Preview.call(rule)[:result][:count]
    private_plan = other.action_plans.create!(name: "Plano RH", sector: :hr, public: false)
    rule.action_key = "create_task"
    rule.action_config = { title: "Teste", bucket_id: private_plan.buckets.first.id.to_s }
    refute rule.valid?
  end

  test "fleet snapshots count status and report missing days without creating false zeros" do
    availability = FleetAvailability.create!(user: @owner, date: Date.current, agreed_quantity: 0)
    availability.fleet_availability_items.create!(plate: plates(:one), status: :unavailable, reason: :maintenance, position: 0)
    rule = task_rule(source_key: "fleet", filters: { status: "unavailable" })
    assert_equal 1, Automations::Preview.call(rule)[:result][:count]
    rule.period = "yesterday"
    preview = Automations::Preview.call(rule)
    assert_equal false, preview[:result][:available]
    assert_equal "skipped", run_automation(rule).status
    @owner.update!(sector: :hr)
    refute rule.reload.valid?
  end

  test "action errors roll back business writes and produce a failure record" do
    rule = task_rule(action_key: "create_task", action_config: { title: "Teste" })
    TaskActivityService.stub(:log, ->(**_) { raise "simulated action failure" }) do
      assert_no_difference ["Task.count", "Tasklist.count"] do
        assert_equal "failed", run_automation(rule).status
      end
    end
    assert_equal 1, rule.automation_runs.count
    refute_includes rule.automation_runs.last.message, "simulated"
  end

  test "unsupported code URLs and unknown template variables cannot be configured" do
    rule = task_rule(source_key: "sql")
    refute rule.valid?
    rule.source_key = "tasks"
    rule.action_key = "http"
    refute rule.valid?
    rule.action_key = "notify"
    rule.action_config = { title: "{{senha}}" }
    refute rule.valid?
  end

  test "sum average and count share the connector without fuel-specific logic" do
    create_automation_expense(100)
    create_automation_expense(200)
    rule = finance_rule(operation: "average")
    assert_equal BigDecimal("150"), Automations::Preview.call(rule)[:result][:value]
    rule.operation = "count"
    @indicator.update!(value_type: :integer)
    assert_equal BigDecimal("2"), Automations::Preview.call(rule)[:result][:value]
  end

  test "multiple categories sum each invoice once including equal totals and multiple invoice numbers" do
    forklift = BudgetCategory.create!(name: "Manutenção empilhadeiras", sector: :frota)
    unrelated = BudgetCategory.create!(name: "Outra despesa", sector: :frota)
    create_automation_expense(100)
    invoice = create_automation_expense(40, category: forklift)
    invoice.invoice_numbers.create!(number: "Segunda NF", amount: 60, cost_center: @center)
    invoice.save!
    create_automation_expense(500, category: unrelated)
    create_automation_expense(900, category: forklift, date: 1.month.ago.to_date)
    rule = finance_rule(filters: { "budget_category_ids" => [@category.id, forklift.id, @category.id] })
    preview = Automations::Preview.call(rule)
    assert_equal 2, preview[:result][:count]
    assert_equal BigDecimal("200"), preview[:result][:value]
    assert_equal "success", run_automation(rule).status
    assert_equal "200.0", @routine.routine_values.sole.value
    assert_equal "unchanged", run_automation(rule).status
    rule.operation = "average"
    assert_equal BigDecimal("100"), Automations::Preview.call(rule)[:result][:value]
    rule.operation = "count"
    @indicator.update!(value_type: :integer)
    assert_equal BigDecimal("2"), Automations::Preview.call(rule)[:result][:value]
  end

  test "losing access to one selected category blocks the entire write instead of recording a partial total" do
    second = BudgetCategory.create!(name: "Manutenção caminhões", sector: :frota)
    create_automation_expense(100)
    create_automation_expense(200, category: second)
    rule = finance_rule(filters: { "budget_category_ids" => [@category.id, second.id] })
    assert_equal "success", run_automation(rule).status
    second.update!(sector: :rh)
    assert_equal "skipped", run_automation(rule).status
    assert_equal "300.0", @routine.routine_values.sole.value
  end

  test "invalid selected IDs and mixed sectors are rejected and empty lists preserve all-category semantics" do
    create_automation_expense(100)
    rule = finance_rule(filters: { "budget_category_ids" => [""] })
    assert_equal BigDecimal("100"), Automations::Preview.call(rule)[:result][:value]
    invalid = [@category.id, [-1], [1.5], [nil], [{ "id" => @category.id }], [@category.id, 9_999_999_999]]
    invalid.each do |ids|
      rule.filters = { "budget_category_ids" => ids }
      refute rule.valid?, ids.inspect
    end
    rule.filters = { "budget_category_id" => @category.id, "budget_category_ids" => [@category.id] }
    refute rule.valid?
    hr = BudgetCategory.create!(name: "Manutenção RH", sector: :rh)
    @owner.update!(role: :admin)
    rule.filters = { "budget_category_ids" => [@category.id, hr.id], "sector" => "frota" }
    refute rule.valid?
    rule.filters.delete("sector")
    assert rule.valid?
  end
end
