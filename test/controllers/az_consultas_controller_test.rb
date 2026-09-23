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
    AzMapa.create!(data: "2026-09-13", tipo: :eficiencia_carregamento, turno: [0, 2], resultado: 95, atingiu_meta: true)
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

  test "operator consultation pays weekday EFC but not Sunday EFC" do
    AzMapa.delete_all
    operator = operators(:one)
    operator.update!(turno: 0, matricula: "EFC-SUNDAY")
    rate = ParametroCalculo.find_or_initialize_by(categoria: "operador", nome: "valor_efc")
    rate.update!(valor: 12)
    ["2026-09-12", "2026-09-13"].each do |date|
      AzMapa.create!(data: date, tipo: :eficiencia_carregamento, turno: [0, 2], resultado: 95, atingiu_meta: true)
    end
    get az_consulta_path, params: { matricula: operator.matricula, turno: 0, periodo_mes: 9, periodo_ano: 2026 }
    assert_response :success
    assert_select ".az-overview-card--total .az-overview-value", text: "R$ 12,00"
    assert_select "tbody tr", text: /13\/09\/2026/ do
      assert_select "td", text: /R\$ 0,00/
    end
  end

  test "On Demand displays remunerated units separately from imported records" do
    helper = az_ajudantes(:one)
    helper.update!(nome: "Teste Unidades")
    source = AzRvImport.create!(source_type: "ondemand", original_filename: "units.csv", file_digest: "units")
    [["Repack - Lata", "98"], ["Blitz carregamento", "8"], ["5S-", "1"], ["Colocar Fitilho", "10"]].each_with_index do |(name, observation), index|
      AzRvOnDemandActivity.create!(az_rv_import: source, source_key: "units-#{index}", employee_name: helper.nome,
        employee_key: "teste unidades", activity: name, observation: observation, created_at_source: Time.zone.local(2026, 8, 11))
    end
    get az_consulta_path, params: { perfil: "ajudante", matricula: helper.matricula, periodo_mes: 8, periodo_ano: 2026 }
    assert_response :success
    assert_select ".az-overview-detail", text: /103 unidades · 4 registros importados/
    assert_select "td[data-label='On Demand']", text: /103 · R\$ 22,60/
    assert_select "td[data-label='Atividade']", text: "5S-", count: 0
    dashboard = AzDashboardService.new(start_date: Date.new(2026, 7, 19), end_date: Date.new(2026, 8, 18)).call
    row = dashboard.helpers.find { |item| item[:person].id == helper.id }
    assert_equal 103, row[:activities]
    assert_equal BigDecimal("22.60"), row[:activity_value]
  end

  test "helper consultation matches an imported name truncated at the end" do
    helper = az_ajudantes(:one)
    helper.update!(nome: "VITOR MANOEL MATOS RIBEIRO DA ROCHA")
    source = AzRvImport.create!(source_type: "ondemand", original_filename: "truncated.csv", file_digest: "truncated-name")
    AzRvOnDemandActivity.create!(
      az_rv_import: source,
      source_key: "truncated-name-1",
      employee_name: "VITOR MANOEL MATOS RIBEIRO DA",
      employee_key: "vitor manoel matos ribeiro da",
      activity: "Repack - Lata",
      observation: "87",
      created_at_source: Time.zone.local(2026, 8, 11)
    )

    get az_consulta_path, params: { perfil: "ajudante", matricula: helper.matricula, periodo_mes: 8, periodo_ano: 2026 }

    assert_response :success
    assert_select ".az-overview-card .az-overview-label", text: "On Demand"
    assert_includes response.body, "87 unidades · 1 registros importados"
    assert_select ".az-overview-card--total .az-overview-value", text: "R$ 17,40"
  end

end
