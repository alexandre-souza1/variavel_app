require "test_helper"

class ParametroCalculosControllerTest < ActionDispatch::IntegrationTest
  test "index groups parameters and uses shared page components" do
    parameter = create_parameter
    get parametro_calculos_path

    assert_response :success
    assert_select ".app-page.calculation-parameters-page"
    assert_select ".parameters-category h2", text: /Motorista/
    assert_select ".parameters-name a[href=?]", parametro_calculo_path(parameter), text: "Valor entrega"
    assert_select "a[href=?]", edit_parametro_calculo_path(parameter)
    assert_select "a[href=?]", new_parametro_calculo_path
    assert_select ".driver-report-container", count: 0
  end

  test "search matches displayed names and combines with category filter" do
    parameter = create_parameter
    other_category = create_parameter(categoria: "ajudante", valor: 12)
    other_name = create_parameter(nome: "bonus_presenca")

    get parametro_calculos_path, params: { q: "VALOR ENTREGA", categoria: "motorista" }

    assert_response :success
    assert_select ".parameters-name a[href=?]", parametro_calculo_path(parameter)
    assert_select ".parameters-name a[href=?]", parametro_calculo_path(other_category), count: 0
    assert_select ".parameters-name a[href=?]", parametro_calculo_path(other_name), count: 0
    assert_select "input[name=q][value=?]", "VALOR ENTREGA"
    assert_select "select[name=categoria] option[selected][value=?]", "motorista"
    assert_select "a[href=?]", parametro_calculos_path, text: "Limpar"
  end

  test "search treats wildcard characters literally" do
    parameter = create_parameter(nome: "taxa_10%")
    other = create_parameter

    get parametro_calculos_path, params: { q: "%" }

    assert_response :success
    assert_select ".parameters-name a[href=?]", parametro_calculo_path(parameter)
    assert_select ".parameters-name a[href=?]", parametro_calculo_path(other), count: 0
  end

  test "search also matches category labels with spaces" do
    parameter = create_parameter(categoria: "motorista_van")
    get parametro_calculos_path, params: { q: "MOTORISTA VAN" }
    assert_response :success
    assert_select ".parameters-name a[href=?]", parametro_calculo_path(parameter)
  end

  test "no search results offer a way to clear filters" do
    get parametro_calculos_path, params: { q: "parametro_inexistente_987" }

    assert_response :success
    assert_select ".parameters-empty h2", text: "Nenhum parâmetro encontrado"
    assert_select ".parameters-category", count: 0
    assert_select "a[href=?]", parametro_calculos_path, text: "Limpar filtros"
  end

  test "users without edit permissions can inspect parameters without edit actions" do
    parameter = create_parameter
    users(:one).update!(role: :user)

    get parametro_calculos_path
    assert_response :success
    assert_select ".parameters-name a[href=?]", parametro_calculo_path(parameter)
    assert_select "a[href=?]", new_parametro_calculo_path, count: 0
    assert_select "a[href=?]", edit_parametro_calculo_path(parameter), count: 0

    get parametro_calculo_path(parameter)
    assert_response :success
    assert_select "a[href=?]", edit_parametro_calculo_path(parameter), count: 0
  end

  test "detail lists recorded effective dates newest first" do
    parameter = create_parameter
    future_date = Date.current.next_month
    CalculationRateVersion.create!(categoria: parameter.categoria, nome: parameter.nome,
      valor: 30, effective_on: future_date)

    get parametro_calculo_path(parameter)

    assert_response :success
    assert_select ".parameters-history tbody tr:first-child td:first-child", text: I18n.l(future_date)
    assert_select ".parameters-history tbody tr", count: 2
  end

  test "import screen keeps the existing upload destination" do
    get import_parametro_calculos_path
    assert_response :success
    assert_select "form[action=?][enctype=?]", import_csv_parametro_calculos_path, "multipart/form-data"
    assert_select "input[type=file][name=file][required]"
  end

  private

  def create_parameter(**attributes)
    ParametroCalculo.create!({ categoria: "motorista", nome: "valor_entrega", valor: 25 }.merge(attributes))
  end
end
