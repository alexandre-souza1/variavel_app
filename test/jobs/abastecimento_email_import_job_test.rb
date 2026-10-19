require "test_helper"
require "minitest/mock"

class AbastecimentoEmailImportJobTest < ActiveJob::TestCase
  test "shows imported and ignored counts along with errors when import partially succeeds" do
    notification = Notification.create!(
      user: users(:one), kind: "abastecimento_email_import_progress",
      title: "Importação iniciada", body: "Consultando e-mails"
    )
    date = Date.new(2026, 10, 17)
    result = AbastecimentoEmailImporter::Result.new(
      date: date, processed: 6, skipped: 1, errors: ["NF-e 110210: nota sem número"], invoice_ids: []
    )
    AbastecimentoEmailImporter.stub(:call, result) do
      AbastecimentoEmailImportJob.perform_now(notification.id, date)
    end

    notification.reload
    assert_equal "abastecimento_email_import_finished", notification.kind
    assert_match "concluída com pendências", notification.title
    assert_match "17/10/2026", notification.body
    assert_match "Importados: 6. Ignorados: 1.", notification.body
    assert_match "NF-e 110210: nota sem número", notification.body
  end
end
