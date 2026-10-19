require "test_helper"

class InvoiceEmailImportSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @setting = InvoiceEmailImportSetting.current
    @frame_headers = { "Turbo-Frame" => "invoice-import-settings-form" }
  end

  test "index lazily loads settings inside a collapsed accordion" do
    get invoices_path

    assert_response :success
    assert_select '#invoice-import-drawer button[data-bs-target="#invoice-import-settings-panel"][aria-expanded="false"]'
    assert_select 'turbo-frame#invoice-import-settings-form[loading="lazy"]' do |frames|
      assert_equal edit_invoice_email_import_setting_path, frames.first["src"]
    end
    assert_select 'input[name="invoice_email_import_setting[sender_email]"]', count: 0
  end

  test "frame request renders the settings form without navigating to another page" do
    get edit_invoice_email_import_setting_path, headers: @frame_headers

    assert_response :success
    assert_no_match(/<html[\s>]/i, response.body)
    assert_select "turbo-frame#invoice-import-settings-form form" do
      assert_select 'input[name="invoice_email_import_setting[sender_email]"]'
      assert_select 'input[name="invoice_email_import_setting[imap_folder]"]'
      assert_select 'input[name="invoice_email_import_setting[schedule_time]"]'
      %w[purchaser_id budget_category_id fallback_cost_center_id].each do |field|
        assert_select "select[name='invoice_email_import_setting[#{field}]']"
      end
    end
  end

  test "saves settings and returns confirmation in the same frame" do
    patch invoice_email_import_setting_path, headers: @frame_headers, params: {
      invoice_email_import_setting: {
        sender_email: "posto@example.test", imap_folder: "INBOX/Notas", schedule_time: "08:30",
        purchaser_id: users(:one).id, budget_category_id: budget_categories(:one).id,
        fallback_cost_center_id: cost_centers(:one).id
      }
    }

    assert_response :success
    @setting.reload
    assert_equal "posto@example.test", @setting.sender_email
    assert_equal "INBOX/Notas", @setting.imap_folder
    assert_equal "08:30", @setting.schedule_time
    assert_equal users(:one).id, @setting.purchaser_id
    assert_equal budget_categories(:one).id, @setting.budget_category_id
    assert_equal cost_centers(:one).id, @setting.fallback_cost_center_id
    assert_select 'turbo-frame#invoice-import-settings-form [role="status"]', text: "Configuração salva com sucesso."
  end

  test "validation errors keep the form and entered values inside the accordion" do
    original_time = @setting.schedule_time
    patch invoice_email_import_setting_path, headers: @frame_headers, params: {
      invoice_email_import_setting: { schedule_time: "25:00", imap_folder: "INBOX/Notas" }
    }

    assert_response :unprocessable_entity
    assert_equal original_time, @setting.reload.schedule_time
    assert_select 'turbo-frame#invoice-import-settings-form [role="alert"]', /HH:MM/
    assert_select 'input[name="invoice_email_import_setting[imap_folder]"][value="INBOX/Notas"]'
  end

  test "standalone settings page keeps working" do
    get edit_invoice_email_import_setting_path
    assert_response :success
    assert_select "h1", text: "Importação de invoices por e-mail"

    patch invoice_email_import_setting_path, params: { invoice_email_import_setting: { schedule_time: "09:00" } }
    assert_redirected_to edit_invoice_email_import_setting_path
    assert_equal "09:00", @setting.reload.schedule_time
  end

  test "settings remain restricted to admin or finance users for frame requests" do
    users(:one).update!(role: :user, sector: :fleet)
    get edit_invoice_email_import_setting_path, headers: @frame_headers
    assert_redirected_to root_path

    patch invoice_email_import_setting_path, headers: @frame_headers,
          params: { invoice_email_import_setting: { schedule_time: "09:00" } }
    assert_redirected_to root_path
    assert_not_equal "09:00", @setting.reload.schedule_time
  end
end
