require "test_helper"
require "minitest/mock"

class WmsTaskImportJobTest < ActiveJob::TestCase
  test "imports stored CSV after the original upload has disappeared" do
    upload = Tempfile.new(["tasks", ".csv"])
    upload.write("Usuário;Tipo;Tarefa\nAjudante Teste;Blitz Refugo;123456\n")
    upload.rewind
    job = WmsTaskImportJob.enqueue_upload(upload, users(:one).id, original_filename: "tarefas1.csv")
    blob = ActiveStorage::Blob.find(job.arguments.first.fetch("blob_id"))
    key = blob.key
    storage = blob.service
    upload.close!

    assert_difference "AzRvTask.count", 1 do
      perform_enqueued_jobs(only: WmsTaskImportJob)
    end

    imported = AzRvImport.find_by!(original_filename: "tarefas1.csv")
    assert_equal "completed", imported.status
    assert_equal users(:one), imported.user
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not storage.exist?(key)
  ensure
    upload&.close!
    blob&.purge if blob && ActiveStorage::Blob.exists?(blob.id)
  end

  test "removes stored upload when enqueue fails" do
    assert_no_difference "ActiveStorage::Blob.count" do
      WmsTaskImportJob.stub(:perform_later, false) do
        assert_raises(RuntimeError) do
          WmsTaskImportJob.enqueue_upload(StringIO.new("csv"), nil, original_filename: "tasks.csv")
        end
      end
    end
  end

  test "reports processing errors and cleans up stored upload" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("csv"), filename: "tasks.csv")
    job = WmsTaskImportJob.new
    errors = []
    job.stub(:show_result, ->(*args) { errors << args }) do
      SharedTasksImportService.stub(:new, ->(**args) { raise "CSV inválido" }) do
        job.perform({ "blob_id" => blob.id }, users(:one).id)
      end
    end
    assert_equal [[users(:one).id, "❌ Erro: CSV inválido", true, true]], errors
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test "missing legacy path is displayed as an error" do
    job = WmsTaskImportJob.new
    errors = []
    job.stub(:show_result, ->(*args) { errors << args }) do
      job.perform(Rails.root.join("tmp", "missing-#{SecureRandom.hex}.csv").to_s, users(:one).id)
    end
    assert_equal true, errors.first[2]
    assert_match "Envie o CSV novamente", errors.first[1]
  end
end
