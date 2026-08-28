require "test_helper"

class TaskImportsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_task_import_url
    assert_response :success
  end

  test "should get create" do
    post task_imports_url
    assert_redirected_to new_task_import_url
  end
end
