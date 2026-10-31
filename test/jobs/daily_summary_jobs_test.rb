require "test_helper"
require "minitest/mock"

class DailySummaryJobsTest < ActiveJob::TestCase
  setup do
    travel_to Time.find_zone!("Brasilia").local(2026, 11, 1, 7, 50)
    @user = users(:two)
    @user.update!(daily_summary_enabled: true)
    travel_to Time.find_zone!("Brasilia").local(2026, 11, 1, 8)
  end

  teardown { travel_back }

  test "dispatches at eight for enabled active accounts only and reserves queued work" do
    users(:one).update_columns(daily_summary_enabled: true, daily_summary_next_run_at: Time.current, active: false)

    assert_enqueued_jobs 1, only: DailySummaryJob do
      DailySummaryDispatchJob.perform_now
      DailySummaryDispatchJob.perform_now
    end
    summary = @user.daily_summaries.sole
    assert_equal Date.new(2026, 11, 1), summary.summary_date
    assert_enqueued_with(job: DailySummaryJob, args: [summary.id])
    assert_equal 0, users(:one).daily_summaries.count
  end

  test "never dispatches before eight even if a scheduled date is overdue" do
    travel_to Time.find_zone!("Brasilia").local(2026, 11, 1, 7, 59)
    @user.update_columns(daily_summary_next_run_at: 1.day.ago)

    assert_no_enqueued_jobs(only: DailySummaryJob) { DailySummaryDispatchJob.perform_now }
    assert_equal 0, @user.daily_summaries.count
  end

  test "activation after eight waits until tomorrow" do
    @user.update!(daily_summary_enabled: false)
    @user.update!(daily_summary_enabled: true)

    assert_no_enqueued_jobs(only: DailySummaryJob) { DailySummaryDispatchJob.perform_now }
  end

  test "worker downtime catches up on today's summary without sending previous days" do
    travel 2.days + 1.hour

    assert_enqueued_jobs(1, only: DailySummaryJob) { DailySummaryDispatchJob.perform_now }
    assert_equal [Date.new(2026, 11, 3)], @user.daily_summaries.pluck(:summary_date)
  end

  test "expired queue reservations are retried after a lost job" do
    DailySummaryDispatchJob.perform_now
    summary = @user.daily_summaries.sole
    travel DailySummary::LEASE_DURATION

    assert_no_difference "DailySummary.count" do
      assert_enqueued_jobs(1, only: DailySummaryJob) { DailySummaryDispatchJob.perform_now }
    end
    assert_enqueued_with(job: DailySummaryJob, args: [summary.id])
  end

  test "delivery creates exactly one notification and retains the full Gemini answer separately from chat" do
    summary = pending_summary
    with_generator do
      assert_no_difference ["AiConversation.count", "AiMessage.count"] do
        assert_difference -> { @user.notifications.count }, 1 do
          2.times { DailySummaryJob.perform_now(summary.id) }
        end
      end
    end

    notification = summary.reload.notification
    assert summary.delivered?
    assert_equal "**Agenda**\n- Conferir tarefas", summary.content
    assert_equal "daily_summary", notification.kind
    assert_equal Rails.application.routes.url_helpers.daily_summary_path(summary), notification.action_url
    assert_equal Time.find_zone!("Brasilia").local(2026, 11, 2, 8), @user.reload.daily_summary_next_run_at
    assert_no_enqueued_jobs(only: DailySummaryJob) { DailySummaryDispatchJob.perform_now }
  end

  test "deleting the notification does not resend today's summary" do
    summary = pending_summary
    with_generator { DailySummaryJob.perform_now(summary.id) }
    summary.reload.notification.destroy!

    with_generator(-> { flunk "Must not regenerate a delivered summary" }) do
      assert_no_difference("Notification.count") { DailySummaryJob.perform_now(summary.id) }
    end
  end

  test "disabling or retiring before queued execution prevents generation" do
    summary = pending_summary
    @user.update!(daily_summary_enabled: false)
    with_generator(-> { flunk "Disabled user must not generate" }) { DailySummaryJob.perform_now(summary.id) }

    @user.update_columns(daily_summary_enabled: true, daily_summary_next_run_at: Time.current, active: false)
    with_generator(-> { flunk "Inactive user must not generate" }) { DailySummaryJob.perform_now(summary.id) }
    assert summary.reload.pending?
    assert_nil summary.notification
  end

  test "disabling while Gemini is responding prevents notification delivery" do
    summary = pending_summary
    with_generator(-> { @user.update!(daily_summary_enabled: false); answer }) do
      assert_no_difference("Notification.count") { DailySummaryJob.perform_now(summary.id) }
    end
    assert_nil summary.reload.delivered_at
  end

  test "changed sector during generation discards the answer and rechecks permissions on retry" do
    summary = pending_summary
    with_generator(-> { @user.update!(sector: :warehouse); answer }) do
      assert_no_difference("Notification.count") { DailySummaryJob.perform_now(summary.id) }
    end
    assert summary.reload.pending?
    assert_nil summary.content
  end

  test "provider failures are retained for retry and not falsely marked delivered" do
    summary = pending_summary
    with_generator(-> { raise AiAssistant::Responder::Unavailable.new(:quota) }) do
      assert_no_difference("Notification.count") { DailySummaryJob.perform_now(summary.id) }
    end
    assert summary.reload.pending?
    assert_equal "quota", summary.last_error
    assert_operator summary.next_attempt_at, :>, Time.current
    assert_equal 1, summary.attempts
    assert_nil summary.delivered_at

    with_generator(-> { flunk "Duplicate jobs must respect the retry delay" }) { DailySummaryJob.perform_now(summary.id) }

    travel_to summary.next_attempt_at
    assert_enqueued_jobs(1, only: DailySummaryJob) { DailySummaryDispatchJob.perform_now }
    with_generator { DailySummaryJob.perform_now(summary.id) }
    assert summary.reload.delivered?
    assert_equal 2, summary.attempts
  end

  test "an active processing lease prevents simultaneous generation and a stale lease can recover" do
    summary = pending_summary
    summary.update!(status: :processing, processing_token: "old", processing_started_at: Time.current)
    with_generator(-> { flunk "An active attempt already owns the summary" }) { DailySummaryJob.perform_now(summary.id) }

    travel 6.minutes
    with_generator { DailySummaryJob.perform_now(summary.id) }
    assert summary.reload.delivered?
  end

  test "an expired attempt cannot publish after another worker owns the summary" do
    summary = pending_summary
    with_generator(-> { summary.update!(processing_token: "new-worker"); answer }) do
      assert_no_difference("Notification.count") { DailySummaryJob.perform_now(summary.id) }
    end
    assert_nil summary.reload.delivered_at
  end

  test "old jobs cannot send yesterday's summary after midnight" do
    summary = pending_summary
    travel 1.day
    with_generator(-> { flunk "Old summaries must not be sent" }) { DailySummaryJob.perform_now(summary.id) }
    assert_nil summary.reload.notification
  end

  test "the worker scheduler dispatches summaries even when automation enqueue fails" do
    AutomationDispatchJob.stub(:perform_later, -> { raise ActiveJob::EnqueueError }) do
      assert_enqueued_jobs(1, only: DailySummaryDispatchJob) { Automations::Scheduler.new.dispatch }
    end
  end

  private

  def pending_summary
    @user.daily_summaries.create!(summary_date: Date.current, next_attempt_at: Time.current)
  end

  def answer
    { content: "**Agenda**\n- Conferir tarefas", sources: [{ label: "Entrada", path: "/entrada" }] }
  end

  def with_generator(callback = -> { answer })
    generator = Object.new
    generator.define_singleton_method(:call) { callback.call }
    AiAssistant::DailySummaryGenerator.stub(:new, ->(user:) { assert_equal @user.id, user.id; generator }) { yield }
  end
end
