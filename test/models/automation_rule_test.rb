require "test_helper"
require_relative "../support/automation_setup"

class AutomationRuleTest < ActiveSupport::TestCase
  include AutomationSetup
  setup { setup_automation_data }
  teardown { travel_back }

  test "new rules are paused and schedules use Brasilia time" do
    rule = task_rule(schedule: "daily", execution_hour: 8)
    rule.save!
    assert_not rule.enabled?
    assert_nil rule.next_run_at
    rule.update!(enabled: true)
    assert_equal Time.zone.local(2026, 10, 17, 8), rule.next_run_at
    rule.update!(schedule: "hourly")
    assert_equal Time.zone.local(2026, 10, 16, 11), rule.next_run_at
    rule.update!(enabled: false)
    assert_nil rule.next_run_at
  end

  test "monthly schedules clamp dates and weekly schedules find the next weekday" do
    rule = task_rule(enabled: true, schedule: "monthly", month_day: 31, execution_hour: 8)
    assert_equal Time.zone.local(2026, 2, 28, 8), rule.next_occurrence(after: Time.zone.local(2026, 2, 1, 10))
    rule.schedule, rule.weekday = "weekly", 1
    assert_equal Time.zone.local(2026, 10, 19, 8), rule.next_occurrence
  end

  test "only one enabled rule may own a GEROT indicator" do
    first = finance_rule(enabled: true)
    first.save!
    second = finance_rule(enabled: true)
    refute second.valid?
    assert_match(/outra automação ativa/, second.errors.full_messages.to_sentence)
    second.enabled = false
    assert second.valid?
  end

  test "manual rules have no scheduled run and invalid schedules are rejected" do
    rule = task_rule(enabled: true, schedule: "manual")
    rule.save!
    assert_nil rule.next_run_at
    rule.schedule = "arbitrary cron"
    refute rule.valid?
  end

  test "schedule dispatcher rechecks due state and does not execute twice" do
    rule = task_rule(enabled: true)
    rule.save!
    rule.update_column(:next_run_at, 1.minute.ago)
    assert_difference "Notification.count", 1 do
      AutomationDispatchJob.perform_now
      AutomationDispatchJob.perform_now
    end
    assert_equal 1, rule.automation_runs.count
    assert rule.reload.next_run_at > Time.current
  end
end
