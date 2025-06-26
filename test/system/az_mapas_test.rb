require "application_system_test_case"

class AzMapasTest < ApplicationSystemTestCase
  setup do
    @az_mapa = az_mapas(:one)
  end

  test "visiting the index" do
    visit az_mapas_url
    assert_selector "h1", text: "Az mapas"
  end

  test "should create az mapa" do
    visit az_mapas_url
    click_on "New az mapa"

    check "Atingiu meta" if @az_mapa.atingiu_meta
    fill_in "Data", with: @az_mapa.data
    fill_in "Resultado", with: @az_mapa.resultado
    fill_in "Tipo", with: @az_mapa.tipo
    fill_in "Turno", with: @az_mapa.turno
    click_on "Create Az mapa"

    assert_text "Az mapa was successfully created"
    click_on "Back"
  end

  test "should update Az mapa" do
    visit az_mapa_url(@az_mapa)
    click_on "Edit this az mapa", match: :first

    check "Atingiu meta" if @az_mapa.atingiu_meta
    fill_in "Data", with: @az_mapa.data
    fill_in "Resultado", with: @az_mapa.resultado
    fill_in "Tipo", with: @az_mapa.tipo
    fill_in "Turno", with: @az_mapa.turno
    click_on "Update Az mapa"

    assert_text "Az mapa was successfully updated"
    click_on "Back"
  end

  test "should destroy Az mapa" do
    visit az_mapa_url(@az_mapa)
    click_on "Destroy this az mapa", match: :first

    assert_text "Az mapa was successfully destroyed"
  end
end
