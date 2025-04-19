require "application_system_test_case"

class AjudantesTest < ApplicationSystemTestCase
  setup do
    @ajudante = ajudantes(:one)
  end

  test "visiting the index" do
    visit ajudantes_url
    assert_selector "h1", text: "Ajudantes"
  end

  test "should create ajudante" do
    visit ajudantes_url
    click_on "New ajudante"

    fill_in "Cpf", with: @ajudante.cpf
    fill_in "Data nascimento", with: @ajudante.data_nascimento
    fill_in "Matricula", with: @ajudante.matricula
    fill_in "Nome", with: @ajudante.nome
    fill_in "Promax", with: @ajudante.promax
    click_on "Create Ajudante"

    assert_text "Ajudante was successfully created"
    click_on "Back"
  end

  test "should update Ajudante" do
    visit ajudante_url(@ajudante)
    click_on "Edit this ajudante", match: :first

    fill_in "Cpf", with: @ajudante.cpf
    fill_in "Data nascimento", with: @ajudante.data_nascimento
    fill_in "Matricula", with: @ajudante.matricula
    fill_in "Nome", with: @ajudante.nome
    fill_in "Promax", with: @ajudante.promax
    click_on "Update Ajudante"

    assert_text "Ajudante was successfully updated"
    click_on "Back"
  end

  test "should destroy Ajudante" do
    visit ajudante_url(@ajudante)
    click_on "Destroy this ajudante", match: :first

    assert_text "Ajudante was successfully destroyed"
  end
end
