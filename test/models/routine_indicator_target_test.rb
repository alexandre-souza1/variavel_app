require "test_helper"

class RoutineIndicatorTargetTest < ActiveSupport::TestCase
  test "duration goal accepts minutes above 100" do
    target = routine_indicator_targets(:one)
    target.routine_indicator.update!(value_type: :duration)
    target.goal = "125:30"

    assert target.valid?
  end

  test "duration goal rejects invalid seconds" do
    target = routine_indicator_targets(:one)
    target.routine_indicator.update!(value_type: :duration)
    target.goal = "12:75"

    assert_not target.valid?
  end
end
