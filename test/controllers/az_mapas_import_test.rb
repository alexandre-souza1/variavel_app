require "test_helper"
require "caxlsx"

class AzMapasImportTest < ActionDispatch::IntegrationTest
  test "admin can open import form" do
    get import_az_mapas_path
    assert_response :success
    assert_select "input[type=file][multiple]"
  end

  test "imports percentages and goals and preserves existing days on repeat" do
    with_spreadsheet([[2026, "Março", 1, 0.98, 0.98], [2026, "Março", 2, 0.96, 0.98]]) do |file|
      assert_difference("AzMapa.count", 2) { post import_az_mapas_path, params: { file: file } }
      assert_redirected_to az_mapas_path
      mapa = AzMapa.find_by!(data: Date.new(2026, 3, 1), tipo: :eficiencia_carregamento)
      assert_equal [0, 2], mapa.turno
      assert_in_delta 98, mapa.resultado
      assert mapa.atingiu_meta?
      assert_not AzMapa.find_by!(data: Date.new(2026, 3, 2)).atingiu_meta?
      assert_no_difference("AzMapa.count") { post import_az_mapas_path, params: { file: file } }
      assert_match "2 ignorado(s)", flash[:notice]
    end
  end

  test "invalid later row prevents the entire import" do
    with_spreadsheet([[2026, "Julho", 1, 1, 0.98], [2026, "Julho", 32, 1, 0.98]]) do |file|
      assert_no_difference("AzMapa.count") { post import_az_mapas_path, params: { file: file } }
      assert_response :unprocessable_entity
      assert_match "Linha 5", response.body
    end
  end

  test "rejects missing file and unexpected columns" do
    post import_az_mapas_path
    assert_response :unprocessable_entity
    with_spreadsheet([], headers: ["Data", "Resultado"]) do |file|
      assert_no_difference("AzMapa.count") { post import_az_mapas_path, params: { file: file } }
      assert_response :unprocessable_entity
    end
  end

  test "rejects duplicate dates and invalid percentages" do
    [
      [[2026, "Julho", 1, 1, 0.98], [2026, "Julho", 1, 0.96, 0.98]],
      [[2026, "Julho", 1, "inválido", 0.98]],
      [[2026, "Julho", 1, 1, nil]],
      [[2026, "Julho", 1, -0.5, 0.98]]
    ].each do |rows|
      with_spreadsheet(rows) do |file|
        assert_no_difference("AzMapa.count") { post import_az_mapas_path, params: { file: file } }
        assert_response :unprocessable_entity
      end
    end
  end

  test "partial turn overlap is preserved" do
    existing = AzMapa.create!(data: Date.new(2026, 7, 1), tipo: :eficiencia_carregamento, turno: [0], resultado: 80, atingiu_meta: false)
    with_spreadsheet([[2026, "Julho", 1, 1, 0.98]]) do |file|
      assert_no_difference("AzMapa.count") { post import_az_mapas_path, params: { file: file } }
      assert_equal 80, existing.reload.resultado
    end
  end

  test "non admins cannot import" do
    users(:one).update!(role: :user)
    get import_az_mapas_path
    assert_redirected_to root_path
    assert_no_difference("AzMapa.count") { post import_az_mapas_path }
    assert_redirected_to root_path
  end

  test "imports multiple TMA months in hours and compares minutes including equality" do
    headers = ["ANO", "NOME_MES_ABREV", "DIA", "TR", "Meta"]
    with_spreadsheet([[2026, "Jul", 18, 138, 138]], headers: headers) do |july|
      with_spreadsheet([[2026, "Ago", 1, 119, 138]], headers: headers) do |august|
        with_spreadsheet([[2026, "Set", 17, 303, 138]], headers: headers) do |september|
          files = [july, august, september]
          assert_difference("AzMapa.count", 3) { post import_az_mapas_path, params: { files: files } }
          assert_redirected_to az_mapas_path
          july_map = AzMapa.find_by!(data: Date.new(2026, 7, 18), tipo: :tempo_atendimento)
          assert_equal [0, 1, 2], july_map.turno
          assert_in_delta 2.3, july_map.resultado
          assert july_map.atingiu_meta?
          august_map = AzMapa.find_by!(data: Date.new(2026, 8, 1), tipo: :tempo_atendimento)
          assert_in_delta 119 / 60.0, august_map.resultado
          assert august_map.atingiu_meta?
          september_map = AzMapa.find_by!(data: Date.new(2026, 9, 17), tipo: :tempo_atendimento)
          assert_in_delta 5.05, september_map.resultado
          assert_not september_map.atingiu_meta?
          assert_no_difference("AzMapa.count") { post import_az_mapas_path, params: { files: files } }
          assert_match "3 ignorado(s)", flash[:notice]
        end
      end
    end
  end

  test "invalid TMA in second file prevents saving the batch" do
    with_spreadsheet([[2026, "Julho", 1, 1, 0.98]]) do |efc|
      [nil, -1, "inválido"].each do |value|
        with_spreadsheet([[2026, "Jul", 1, value, 138]], headers: ["ANO", "NOME_MES_ABREV", "DIA", "TR", "Meta"]) do |tma|
          assert_no_difference("AzMapa.count") { post import_az_mapas_path, params: { files: [efc, tma] } }
          assert_response :unprocessable_entity
          assert_match "Linha 4", response.body
        end
      end
    end
  end

  test "EFC and TMA can share a date but duplicate indicators across files are rejected" do
    with_spreadsheet([[2026, "Julho", 1, 1, 0.98]]) do |efc|
      with_spreadsheet([[2026, "Jul", 1, 111, 138]], headers: ["ANO", "NOME_MES_ABREV", "DIA", "TR", "Meta"]) do |tma|
        assert_difference("AzMapa.count", 2) { post import_az_mapas_path, params: { files: [efc, tma] } }
        assert_redirected_to az_mapas_path
        assert_no_difference("AzMapa.count") { post import_az_mapas_path, params: { files: [tma, tma] } }
        assert_response :unprocessable_entity
        assert_match "datas repetidas", response.body
      end
    end
  end

  test "EFD imports dates percentages and goals into turn B and skips missing results" do
    rows = [[Date.new(2026, 7, 1), 0.9, 0.9922], ["02/07/2026", 0.9, 0.9],
            ["2026-07-03", 0.9, 0.89], ["04/07/2026", 0.9, 0], ["05/07/2026", 0.9, nil]]
    with_spreadsheet(rows, headers: ["Data", "Meta (%) - QUANTO MAIOR MELHOR", "Realizado (%)"]) do |file|
      assert_difference("AzMapa.count", 4) { post import_az_mapas_path, params: { files: [file] } }
      assert_redirected_to az_mapas_path
      assert_match "1 dia(s) sem resultado", flash[:notice]
      maps = AzMapa.where(tipo: :eficiencia_descarga).where(data: Date.new(2026, 7, 1)..Date.new(2026, 7, 5)).order(:data)
      assert_equal [[1]] * 4, maps.map(&:turno)
      assert_in_delta 99.22, maps.first.resultado
      assert_equal [true, true, false, false], maps.map(&:atingiu_meta?)
      assert_equal 0, maps.last.resultado
      assert_no_difference("AzMapa.count") { post import_az_mapas_path, params: { files: [file] } }
      assert_match "4 ignorado(s)", flash[:notice]
    end
  end

  test "invalid EFD cancels the entire batch including valid EFC" do
    with_spreadsheet([[2026, "Julho", 1, 1, 0.98]]) do |efc|
      [["31/02/2026", 0.9, 1], ["01/07/2026", nil, 1], ["01/07/2026", 0.9, "erro"]].each do |row|
        with_spreadsheet([row], headers: ["Data", "Meta (%) - QUANTO MAIOR MELHOR", "Realizado (%)"]) do |efd|
          assert_no_difference("AzMapa.count") { post import_az_mapas_path, params: { files: [efc, efd] } }
          assert_response :unprocessable_entity
        end
      end
    end
  end

  test "EFD and EFC on the same date are separate indicators" do
    with_spreadsheet([[2026, "Julho", 1, 1, 0.98]]) do |efc|
      with_spreadsheet([["01/07/2026", 0.9, 1]], headers: ["Data", "Meta (%) - QUANTO MAIOR MELHOR", "Realizado (%)"]) do |efd|
        assert_difference("AzMapa.count", 2) { post import_az_mapas_path, params: { files: [efc, efd] } }
        assert_redirected_to az_mapas_path
      end
    end
  end

  private

  def with_spreadsheet(rows, headers: ["Ano", "Mês", "Dia", "% EFC", "Meta"])
    Tempfile.create(["az-import", ".xlsx"]) do |tempfile|
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Sheet1") do |sheet|
        sheet.add_row ["Filtros aplicados"]
        sheet.add_row []
        sheet.add_row headers
        rows.each { |row| sheet.add_row row }
      end
      package.serialize(tempfile.path)
      yield Rack::Test::UploadedFile.new(tempfile.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    end
  end
end
