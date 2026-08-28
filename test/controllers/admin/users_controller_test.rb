require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:two)
  end

  test "should get index" do
    get admin_users_index_url
    assert_response :success
  end

  test "should get edit" do
    get edit_admin_user_url(@user)
    assert_response :success
  end

  test "should get update" do
    patch admin_user_url(@user), params: { user: { email: @user.email } }
    assert_response :success
  end
end
