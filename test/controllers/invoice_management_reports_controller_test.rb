require 'test_helper'
require 'minitest/mock'

class InvoiceManagementReportsControllerTest < ActionDispatch::IntegrationTest
  test 'PDF requires a complete valid month and year even on direct requests' do
    [{}, { month: 9 }, { year: 2026 }, { month: 13, year: 2026 }, { month: 9, year: '2026invalid' }].each do |params|
      Faraday.stub(:post, ->(*) { flunk 'Invalid periods must not call Gemini' }) do
        get dashboard_invoices_path(format: :pdf), params: params
      end
      assert_response :unprocessable_entity
      assert_includes response.body, 'Selecione mês e ano'
    end
  end

  test 'PDF downloads the exact calendar month without requiring an API key' do
    previous = ENV.delete('GEMINI_API_KEY')
    Faraday.stub(:post, ->(*) { flunk 'Management reports are generated locally' }) do
      get dashboard_invoices_path(format: :pdf), params: { month: 9, year: 2026, sector: 'FROTA' }
    end
    assert_response :success
    assert_equal 'application/pdf', response.media_type
    assert response.body.start_with?('%PDF-')
    assert_includes response.headers['Content-Disposition'], '2026-09-01-2026-09-30.pdf'
  ensure
    ENV['GEMINI_API_KEY'] = previous
  end

  test 'PDF authenticates and enforces finance sector access' do
    sign_out users(:one)
    get dashboard_invoices_path(format: :pdf), params: { month: 9, year: 2026 }
    assert_response :unauthorized
    sign_in users(:one)
    users(:one).update!(role: :user, sector: :warehouse)
    get dashboard_invoices_path(format: :pdf), params: { month: 9, year: 2026 }
    assert_response :forbidden
    users(:one).update!(sector: :fleet)
    get dashboard_invoices_path(format: :pdf), params: { month: 9, year: 2026, sector: 'financeiro' }
    assert_response :forbidden
  end

  test 'dashboard offers the report only for a selected period and preserves sector filters' do
    get dashboard_invoices_path
    assert_response :success
    assert_select 'a[href*="dashboard.pdf"]', count: 0
    assert_select '.invoice-report-period-hint', text: /Selecione mês e ano/
    get dashboard_invoices_path, params: { year: 2026 }
    assert_response :success
    assert_select 'a[href*="dashboard.pdf"]', count: 0
    get dashboard_invoices_path, params: { month: 9, year: 2026, sector: 'frota' }
    assert_response :success
    assert_select 'a[href*="dashboard.pdf"][href*="month=9"][href*="year=2026"][href*="sector=frota"]', count: 1
    assert_select '.filter-form select[name="sector"] option[selected][value="frota"]', count: 1
  end
end
