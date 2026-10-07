require "test_helper"

class AjudantesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @ajudante = ajudantes(:one)
  end

  test "should get index" do
    get ajudantes_url
    assert_redirected_to employees_path(employee_sector: 'du', cargo: 'ajudante')
  end

  test "should get new" do
    get new_ajudante_url
    assert_redirected_to new_employee_path(employee_sector: 'du', employee_cargo: 'ajudante')
  end

  test "should create ajudante" do
    assert_difference("Ajudante.count") do
      post ajudantes_url, params: { ajudante: { career_starts_on: '2026-01-01', cpf: @ajudante.cpf, data_nascimento: @ajudante.data_nascimento, matricula: 'AJ-NEW', nome: @ajudante.nome, promax: 'AJ-NEW' } }
    end

    assert_redirected_to ajudante_url(Ajudante.last)
    assert_equal Ajudante.last.matricula, Ajudante.last.employee.matricula
  end

  test "should show ajudante" do
    get ajudante_url(@ajudante)
    assert_response :success
  end

  test "should get edit" do
    get edit_ajudante_url(@ajudante)
    assert_response :success
  end

  test "should update ajudante" do
    patch ajudante_url(@ajudante), params: { ajudante: { cpf: @ajudante.cpf, data_nascimento: @ajudante.data_nascimento, matricula: @ajudante.matricula, nome: @ajudante.nome, promax: @ajudante.promax } }
    assert_redirected_to ajudante_url(@ajudante)
  end

  test "should destroy ajudante" do
    assert_no_difference("Ajudante.count") do
      delete ajudante_url(@ajudante)
    end

    assert_not @ajudante.reload.active?
    assert_redirected_to ajudantes_url
  end
end
