require "test_helper"

class StressTestsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get stress_tests_url
    assert_response :success
  end

  test "should get import" do
    get import_stress_tests_url
    assert_response :success
  end
end
