require "test_helper"

class AzConsultasControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out users(:one) }

  test "should get index" do
    get az_consultas_index_url
    assert_response :success
  end

  test "should get new" do
    get az_consultas_new_url
    assert_response :success
  end

  test "should get show" do
    get az_consultas_show_url, params: { matricula: az_ajudantes(:one).matricula, perfil: "ajudante" }
    assert_response :success
  end
  test "task upload queues a shared storage reference" do
    sign_in users(:one)
    upload = Tempfile.new(["tasks", ".csv"])
    upload.write("Usuário;Tipo;Tarefa\nAjudante Teste;Blitz Refugo;123456\n")
    upload.rewind

    assert_enqueued_with(job: WmsTaskImportJob) do
      post az_consultas_import_url, params: {
        tasks_file: Rack::Test::UploadedFile.new(upload.path, "text/csv")
      }
    end

    assert_redirected_to az_consultas_import_url
    assert_match "Tarefas WMS/refugo enviadas", flash[:notice]
    arguments = ActiveJob::Arguments.deserialize(enqueued_jobs.last[:args])
    blob = ActiveStorage::Blob.find(arguments.first.fetch("blob_id"))
    assert_equal File.binread(upload.path), blob.download
    assert_equal users(:one).id, arguments.second
  ensure
    upload&.close!
    blob&.purge
  end

end
