require "test_helper"

class FleetAvailabilitySettingTest < ActiveSupport::TestCase
  test "calculates the lock time in the application timezone" do
    setting = FleetAvailabilitySetting.new(auto_lock_time: "08:30")

    assert_equal "08:30", setting.auto_lock_at(Date.new(2026, 8, 28)).strftime("%H:%M")
  end

  test "rejects invalid lock times" do
    setting = FleetAvailabilitySetting.new(auto_lock_time: "25:99")

    assert_not setting.valid?
    assert_includes setting.errors[:auto_lock_time], "deve estar no formato HH:MM"
  end
end
