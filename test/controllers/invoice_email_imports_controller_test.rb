require "test_helper"

class InvoiceEmailImportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "enqueues the selected date and shows it in the progress notification" do
    date = Date.new(2026, 10, 17)
    assert_enqueued_with(job: AbastecimentoEmailImportJob, args: ->(args) { args.last == date }) do
      post import_abastecimento_invoices_path, params: { import_date: "2026-10-17" }
    end

    progress = users(:one).notifications.order(:id).last
    assert_equal "abastecimento_email_import_progress", progress.kind
    assert_match "17/10/2026", progress.body
    assert_redirected_to invoices_path(import_notification_id: progress.id, import_date: "2026-10-17")
  end

  test "defaults to yesterday when no date is sent" do
    travel_to Time.zone.local(2026, 10, 19, 0, 30) do
      assert_enqueued_with(job: AbastecimentoEmailImportJob, args: ->(args) { args.last == Date.new(2026, 10, 18) }) do
        post import_abastecimento_invoices_path
      end
    end
  end

  test "invalid dates create neither a job nor a progress notification" do
    ["invalid", "2026-02-30"].each do |date|
      assert_no_difference "Notification.count" do
        assert_no_enqueued_jobs do
          post import_abastecimento_invoices_path, params: { import_date: date }
        end
      end
      assert_redirected_to invoices_path
      assert_match "data válida", flash[:alert]
    end
  end
end
