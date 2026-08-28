require "test_helper"

class AzConsultasControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out users(:one) }

  test "should get index" do
    get az_consultas_index_url
    assert_response :success
  end

  test "should get new" do
    get az_consultas_new_url
    assert_response :success
  end

  test "should get show" do
    get az_consultas_show_url, params: { matricula: az_ajudantes(:one).matricula, perfil: "ajudante" }
    assert_response :success
  end
end
