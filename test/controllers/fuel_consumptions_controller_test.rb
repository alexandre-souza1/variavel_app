require "test_helper"

class FuelConsumptionsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get fuel_consumptions_index_url
    assert_response :success
  end

  test "dashboard renders filtered API data and emissions" do
    GasolaSupply.create!(external_id: 'dashboard-row', registration: 'TEAM-X', plate: 'ABC-1234',
      concluded_at: Time.zone.local(2026, 9, 10), status: 'CONCLUDED', category: 'veículo', fuel: 'dieselS10',
      distance: 400, liters: 100, goal: 3, co2_emission: 268)
    get fuel_consumptions_url, params: { from: '2026-08-21', to: '2026-09-20', registration: 'TEAM-X' }
    assert_response :success
    assert_select 'h1', /Consumo do time/
    assert_select 'section[aria-label="Emissões de CO₂"]', /268,00/
    assert_select 'td', text: 'ABC-1234'
  end

  test "invalid dates redirect with a useful error" do
    get fuel_consumptions_url, params: { from: 'invalid', to: '2026-09-20' }
    assert_redirected_to fuel_consumptions_path
    assert flash[:alert].present?
  end

  test "dashboard requires authentication" do
    sign_out users(:one)
    get fuel_consumptions_url
    assert_redirected_to new_user_session_path
  end

  test "should get new" do
    get fuel_consumptions_new_url
    assert_response :success
  end

  test "should get create" do
    post fuel_consumptions_url
    assert_redirected_to new_fuel_consumption_url
  end
end
