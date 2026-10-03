require 'test_helper'

class PcdsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @date = Date.new(2026, 10, 2)
  end

  test 'DU and admins access PCD and other sectors and mechanics cannot access its endpoints' do
    get pcd_path(date: @date)
    assert_response :success
    assert_select '.pcd-page h1', text: 'PCD'
    assert_select '#duDropdown + ul a[href=?]', pcd_path, text: 'PCD'
    assert_select '#rhDropdown + ul a[href=?]', pcd_path, count: 0
    users(:one).update!(role: :user, sector: :du)
    get pcd_path(date: @date)
    assert_response :success
    users(:one).update!(role: :supervisor, sector: :hr)
    get pcd_path(date: @date)
    assert_response :forbidden
    post preview_routing_pcd_path(date: @date), as: :json
    assert_response :forbidden
    patch pcd_path(date: @date), params: { board: {} }, as: :json
    assert_response :forbidden
    users(:one).update!(role: :mechanical, sector: :du)
    get pcd_path(date: @date)
    assert_response :forbidden
    sign_out users(:one)
    get pcd_path(date: @date)
    assert_redirected_to new_user_session_path
  end

  test 'import previews all routes then save history and print PDF follow the spreadsheet' do
    path = Rails.root.join('test/fixtures/files/pcd_routing.csv')
    assert_no_difference(['PcdPlan.count', 'PcdImport.count', 'PcdChange.count']) do
      post preview_routing_pcd_path(date: @date), params: { file: Rack::Test::UploadedFile.new(path, 'text/csv') }
      assert_response :success
    end
    result = response.parsed_body
    assert_equal 23, result['source']['rows'].size
    cars = result['cars'].map { |car| car.slice('key', *Pcd::Save::EDITABLE) }
    assert_difference(['PcdPlan.count', 'PcdImport.count', 'PcdChange.count'], 1) do
      patch pcd_path(date: @date), params: { board: { reason: 'Importação conferida', expected_revision: -1, routing_token: result['token'], cars: cars } }, as: :json
      assert_response :success
    end
    get pcd_path(date: @date, tab: 'imports')
    assert_select '.pcd-history-item', text: /17 saídas próprias · 6 freteiros · 23 mapas/
    assert_select '.pcd-history-item', text: /FORMOSA DO OESTE/
    assert_difference('PcdChange.count', 1) { get pcd_path(date: @date, format: :pdf) }
    assert_response :success
    assert_equal 'application/pdf', response.media_type
    assert response.body.start_with?('%PDF-')
    get pcd_path(date: @date, tab: 'history')
    assert_select '.pcd-history-item', text: /Impressão PCD SALAS/
    assert_select '.pcd-history-item', text: /Importação conferida/
    post preview_routing_pcd_path(date: @date + 1), params: { file: Rack::Test::UploadedFile.new(path, 'text/csv') }
    assert_response :unprocessable_entity
    assert_match '02/10/2026', response.parsed_body['error']
  end

  test 'invalid dates and missing PDF plans are handled without nil errors' do
    get pcd_path(date: 'invalid')
    assert_redirected_to pcd_path
    get pcd_path(date: @date, format: :pdf)
    assert_redirected_to pcd_path(date: @date)
    get pcd_path(date: @date, tab: 'imports')
    assert_response :success
    assert_select '.pcd-panel', text: /Nenhuma importação salva/
  end
end
