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

  test "helper consultation includes EFC in daily and period totals for every shift" do
    AzMapa.delete_all
    AzMapa.create!(data: "2026-09-18", tipo: :eficiencia_carregamento, turno: [0, 2], resultado: 95, atingiu_meta: true)
    AzMapa.create!(data: "2026-09-19", tipo: :eficiencia_carregamento, turno: [0, 2], resultado: 95, atingiu_meta: true)
    helper = az_ajudantes(:one)
    helper.update!(nome: "Ajudante EFC")

    [0, 1, 2].each do |shift|
      helper.update!(turno: shift)
      get az_consulta_path, params: { perfil: "ajudante", matricula: helper.matricula, periodo_mes: 9, periodo_ano: 2026 }
      assert_response :success
      assert_select ".az-overview-card--total .az-overview-value", text: "R$ 5,00"
      assert_select "td[data-label='EFC']", text: "R$ 5,00", count: 1
      assert_select "td[data-label='Total do dia']", text: "R$ 5,00", count: 1
      assert_select "td[data-label='Data']", text: "18/09/2026", count: 1
    end
  end

end
