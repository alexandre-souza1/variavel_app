require "test_helper"

class AzAjudantesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @az_ajudante = az_ajudantes(:one)
  end

  test "should get index" do
    get az_ajudantes_url
    assert_response :success
  end

  test "should get new" do
    get new_az_ajudante_url
    assert_response :success
  end

  test "should create az_ajudante" do
    assert_difference("AzAjudante.count") do
      post az_ajudantes_url, params: { az_ajudante: { cpf: "999999", data_nascimento: @az_ajudante.data_nascimento, matricula: 999, nome: "Novo ajudante", turno: @az_ajudante.turno } }
    end

    assert_redirected_to az_ajudante_url(AzAjudante.last)
  end

  test "should show az_ajudante" do
    get az_ajudante_url(@az_ajudante)
    assert_response :success
  end

  test "should get edit" do
    get edit_az_ajudante_url(@az_ajudante)
    assert_response :success
  end

  test "should update az_ajudante" do
    patch az_ajudante_url(@az_ajudante), params: { az_ajudante: { cpf: @az_ajudante.cpf, data_nascimento: @az_ajudante.data_nascimento, matricula: @az_ajudante.matricula, nome: "Nome atualizado", turno: @az_ajudante.turno } }
    assert_redirected_to az_ajudante_url(@az_ajudante)
  end

  test "should destroy az_ajudante" do
    assert_no_difference("AzAjudante.count") do
      delete az_ajudante_url(@az_ajudante)
    end

    assert_not @az_ajudante.reload.active?
    assert_redirected_to az_ajudantes_url
  end
end
