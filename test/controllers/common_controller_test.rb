require "test_helper"

class CommonControllerTest < ActionDispatch::IntegrationTest
  test "warehouse home opens AZ dashboard for regular logged in users" do
    users(:one).update!(role: :user, sector: :warehouse)
    get root_path
    assert_response :see_other
    assert_redirected_to dashboard_az_path
    follow_redirect!
    assert_response :success
    assert_select "h1", text: /Dashboard de metas AZ/
    assert_select "a[href='#{dashboard_az_path}']", minimum: 1
  end

  test "explicit variables home remains available to warehouse users" do
    users(:one).update!(role: :user, sector: :warehouse)
    get variaveis_path
    assert_response :success
  end

  test "DU and fleet home destinations are preserved" do
    { du: dashboard_mapas_path, fleet: dashboard_path }.each do |sector, destination|
      users(:one).update!(role: :user, sector: sector)
      get root_path
      assert_redirected_to destination
    end
  end

  test "mechanic with warehouse sector keeps mechanic home and cannot access AZ dashboard" do
    users(:one).update!(role: :mechanical, sector: :warehouse)
    get root_path
    assert_redirected_to mechanic_tasks_path
    get dashboard_az_path
    assert_redirected_to root_path
  end

  test "visitors keep public home" do
    sign_out users(:one)
    get root_path
    assert_response :success
  end
end
