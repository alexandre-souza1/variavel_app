require "application_system_test_case"

class AzAjudantesTest < ApplicationSystemTestCase
  setup do
    @az_ajudante = az_ajudantes(:one)
  end

  test "visiting the index" do
    visit az_ajudantes_url
    assert_selector "h1", text: "Az ajudantes"
  end

  test "should create az ajudante" do
    visit az_ajudantes_url
    click_on "New az ajudante"

    fill_in "Cpf", with: @az_ajudante.cpf
    fill_in "Data nascimento", with: @az_ajudante.data_nascimento
    fill_in "Matricula", with: @az_ajudante.matricula
    fill_in "Nome", with: @az_ajudante.nome
    fill_in "Turno", with: @az_ajudante.turno
    click_on "Create Az ajudante"

    assert_text "Az ajudante was successfully created"
    click_on "Back"
  end

  test "should update Az ajudante" do
    visit az_ajudante_url(@az_ajudante)
    click_on "Edit this az ajudante", match: :first

    fill_in "Cpf", with: @az_ajudante.cpf
    fill_in "Data nascimento", with: @az_ajudante.data_nascimento
    fill_in "Matricula", with: @az_ajudante.matricula
    fill_in "Nome", with: @az_ajudante.nome
    fill_in "Turno", with: @az_ajudante.turno
    click_on "Update Az ajudante"

    assert_text "Az ajudante was successfully updated"
    click_on "Back"
  end

  test "should destroy Az ajudante" do
    visit az_ajudante_url(@az_ajudante)
    click_on "Destroy this az ajudante", match: :first

    assert_text "Az ajudante was successfully destroyed"
  end
end
