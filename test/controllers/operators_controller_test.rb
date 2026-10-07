require "test_helper"

class OperatorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:one)
  end

  test "should get index" do
    get operators_url
    assert_redirected_to employees_path(employee_sector: 'az', cargo: 'operador')
  end

  test "should get new" do
    get new_operator_url
    assert_redirected_to new_employee_path(employee_sector: 'az', employee_cargo: 'operador')
  end

  test "should create operator" do
    assert_difference("Operator.count") do
      post operators_url, params: { operator: { career_starts_on: '2026-01-01', cpf: @operator.cpf, data_nascimento: @operator.data_nascimento, matricula: @operator.matricula, nome: @operator.nome, turno: @operator.turno } }
    end

    assert_redirected_to operator_url(Operator.last)
  end

  test "should show operator" do
    get operator_url(@operator)
    assert_response :success
  end

  test "should get edit" do
    get edit_operator_url(@operator)
    assert_response :success
  end

  test "should update operator" do
    patch operator_url(@operator), params: { operator: { cpf: @operator.cpf, data_nascimento: @operator.data_nascimento, matricula: @operator.matricula, nome: @operator.nome, turno: @operator.turno } }
    assert_redirected_to operator_url(@operator)
  end

  test "should destroy operator" do
    assert_no_difference("Operator.count") do
      delete operator_url(@operator)
    end

    assert_not @operator.reload.active?
    assert_redirected_to operators_url
  end
end
