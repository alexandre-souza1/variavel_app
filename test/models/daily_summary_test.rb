require "test_helper"

class DailySummaryTest < ActiveSupport::TestCase
  test "daily delivery is opt in and defaults to disabled" do
    assert_not User.new.daily_summary_enabled?
    assert_nil User.new.daily_summary_next_run_at
  end

  test "enabling before eight schedules today in Brasilia even with a different application timezone" do
    Time.use_zone("UTC") do
      travel_to Time.utc(2026, 11, 1, 10, 59) do
        user = users(:one)
        user.update!(daily_summary_enabled: true)
        assert_equal Time.utc(2026, 11, 1, 11), user.daily_summary_next_run_at
      end
    end
  end

  test "enabling after eight schedules the next day and handles year rollover" do
    travel_to Time.find_zone!("Brasilia").local(2026, 12, 31, 8, 1) do
      user = users(:one)
      user.update!(daily_summary_enabled: true)
      assert_equal Time.find_zone!("Brasilia").local(2027, 1, 1, 8), user.daily_summary_next_run_at
    end
  end

  test "disabling cancels the next delivery and repeated enabling does not postpone it" do
    travel_to Time.zone.local(2026, 11, 1, 7) do
      user = users(:one)
      user.update!(daily_summary_enabled: true)
      scheduled = user.daily_summary_next_run_at
      travel 2.hours
      user.update!(daily_summary_enabled: true)
      assert_equal scheduled, user.daily_summary_next_run_at
      user.update!(daily_summary_enabled: false)
      assert_nil user.daily_summary_next_run_at
    end
  end

  test "database enforces one summary per person and day" do
    attributes = { user: users(:one), summary_date: Date.current, next_attempt_at: Time.current }
    DailySummary.create!(attributes)
    assert_raises(ActiveRecord::RecordNotUnique) { DailySummary.create!(attributes) }
  end
end
