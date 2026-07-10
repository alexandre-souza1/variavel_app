require "test_helper"

class StressTestsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get stress_tests_index_url
    assert_response :success
  end

  test "should get import" do
    get stress_tests_import_url
    assert_response :success
  end
end
