require "test_helper"

class ChecklistTemplatesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get checklist_templates_index_url
    assert_response :success
  end

  test "should get new" do
    get checklist_templates_new_url
    assert_response :success
  end

  test "should get create" do
    get checklist_templates_create_url
    assert_response :success
  end

  test "should get show" do
    get checklist_templates_show_url
    assert_response :success
  end
end
