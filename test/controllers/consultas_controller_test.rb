require "test_helper"

class ConsultasControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out users(:one) }

  test "should get new" do
    get consultas_new_url
    assert_response :success
  end

  test "should get show" do
    get consultas_show_url, params: { matricula: drivers(:one).matricula, categoria: "motorista" }
    assert_response :success
  end
end
