require "test_helper"

class FuelConsumptionsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get fuel_consumptions_index_url
    assert_response :success
  end

  test "should get new" do
    get fuel_consumptions_new_url
    assert_response :success
  end

  test "should get create" do
    get fuel_consumptions_create_url
    assert_response :success
  end
end
