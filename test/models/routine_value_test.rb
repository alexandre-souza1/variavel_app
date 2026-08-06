require "test_helper"

class RoutineValueTest < ActiveSupport::TestCase
  test "duration value accepts minutes above 100" do
    routine_value = routine_values(:one)
    routine_value.routine_indicator.update!(value_type: :duration)
    routine_value.value = "125:30"

    assert routine_value.valid?
  end

  test "duration value rejects invalid seconds" do
    routine_value = routine_values(:one)
    routine_value.routine_indicator.update!(value_type: :duration)
    routine_value.value = "12:75"

    assert_not routine_value.valid?
  end
end
