require "test_helper"

class ConsultasControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get consultas_new_url
    assert_response :success
  end

  test "should get show" do
    get consultas_show_url
    assert_response :success
  end
end
