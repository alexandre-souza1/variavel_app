require "test_helper"

class AzMapasControllerTest < ActionDispatch::IntegrationTest
  setup do
    @az_mapa = az_mapas(:one)
  end

  test "should get index" do
    get az_mapas_url
    assert_response :success
  end

  test "should get new" do
    get new_az_mapa_url
    assert_response :success
  end

  test "should create az_mapa" do
    assert_difference("AzMapa.count") do
      post az_mapas_url, params: { az_mapa: { atingiu_meta: @az_mapa.atingiu_meta, data: @az_mapa.data, resultado: @az_mapa.resultado, tipo: @az_mapa.tipo, turno: @az_mapa.turno } }
    end

    assert_redirected_to az_mapa_url(AzMapa.last)
  end

  test "should show az_mapa" do
    get az_mapa_url(@az_mapa)
    assert_response :success
  end

  test "should get edit" do
    get edit_az_mapa_url(@az_mapa)
    assert_response :success
  end

  test "should update az_mapa" do
    patch az_mapa_url(@az_mapa), params: { az_mapa: { atingiu_meta: @az_mapa.atingiu_meta, data: @az_mapa.data, resultado: @az_mapa.resultado, tipo: @az_mapa.tipo, turno: @az_mapa.turno } }
    assert_redirected_to az_mapa_url(@az_mapa)
  end

  test "should destroy az_mapa" do
    assert_difference("AzMapa.count", -1) do
      delete az_mapa_url(@az_mapa)
    end

    assert_redirected_to az_mapas_url
  end
end
