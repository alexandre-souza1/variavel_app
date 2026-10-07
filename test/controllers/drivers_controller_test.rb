require "test_helper"

class DriversControllerTest < ActionDispatch::IntegrationTest
  setup { @driver = drivers(:one) }

  test "should get index" do
    get drivers_index_url
    assert_redirected_to employees_path(employee_sector: 'du', cargo: 'motorista')
  end

  test "should get new" do
    get drivers_new_url
    assert_redirected_to new_employee_path(employee_sector: 'du', employee_cargo: 'motorista')
  end

  test "should get edit" do
    get edit_driver_url(@driver)
    assert_response :success
  end

  test "should get show" do
    get driver_url(@driver)
    assert_response :success
  end
end
