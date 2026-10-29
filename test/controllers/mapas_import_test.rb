require 'test_helper'
require 'csv'

class MapasImportTest < ActionDispatch::IntegrationTest
  HEADERS = %w[Entrega Mapa Data MatricMotorista MatricAjud1 MatricAjud2 CxCarreg CxEntreg QtEntregasCarreg(RV) QtEntregasEntreg(RV) Recarga Placa].freeze

  test 'imports Rota and AS with their operation type and original production data' do
    import_rows([
      row(' Rota ', 'IMPORT-ROTA'),
      row(' AS ', 'IMPORT-AS'),
      row('Transferencia', 'IMPORT-OTHER'),
      row('as', 'IMPORT-LOWERCASE')
    ])

    assert_redirected_to mapas_todos_path
    assert_equal 'Rota', Mapa.find_by!(mapa: 'IMPORT-ROTA').entrega
    as_map = Mapa.find_by!(mapa: 'IMPORT-AS')
    assert_equal 'AS', as_map.entrega
    assert_equal '10/07/2026', as_map.data
    assert_equal 'ABC1D23', as_map.plate
    assert_equal 'IMPORT-DRIVER', as_map.matric_motorista
    assert_equal 'IMPORT-HELPER', as_map.matric_ajudante
    assert_equal 1, as_map.fator
    assert_equal 120.5, as_map.cx_total
    assert_equal 100.5, as_map.cx_real
    assert_equal 10, as_map.pdv_total
    assert_equal 9, as_map.pdv_real
    assert_equal 'NAO', as_map.recarga
    assert_not Mapa.exists?(mapa: %w[IMPORT-OTHER IMPORT-LOWERCASE])

    get mapas_todos_path, params: { mapa: 'IMPORT-AS' }
    assert_response :success
    assert_select 'td[data-label="Entrega"]', text: 'AS'
  end

  test 'AS keeps the existing duplicate and helper validation rules' do
    existing = Mapa.create!(mapa: 'IMPORT-EXISTING', entrega: 'Rota')
    invalid_helpers = row('AS', 'IMPORT-INVALID')
    invalid_helpers[5] = invalid_helpers[4]

    assert_difference 'Mapa.count', 1 do
      import_rows([
        row('AS', existing.mapa),
        row('AS', 'IMPORT-DUPLICATE'),
        row('AS', 'IMPORT-DUPLICATE'),
        invalid_helpers,
        row('AS', '')
      ])
    end

    assert_equal 'Rota', existing.reload.entrega
    assert_equal 1, Mapa.where(mapa: 'IMPORT-DUPLICATE').count
    assert_not Mapa.exists?(mapa: 'IMPORT-INVALID')
    assert_includes flash[:notice], 'Ignorados (duplicados)'
    assert_includes flash[:notice], 'não pode ser igual ao Ajudante 1'
    assert_includes flash[:notice], 'mapa vazio'
  end

  private

  def row(entrega, number)
    [entrega, number, '10/07/2026', 'IMPORT-DRIVER', 'IMPORT-HELPER', '0', '120,5', '100,5', '10', '9', 'NAO', 'ABC1D23']
  end

  def import_rows(rows)
    Tempfile.create(['2art', '.csv']) do |file|
      file.write(CSV.generate(col_sep: ';') { |csv| csv << HEADERS; rows.each { |values| csv << values } }.encode('ISO-8859-1'))
      file.rewind
      post import_mapas_path, params: { file: Rack::Test::UploadedFile.new(file.path, 'text/csv') }
    end
  end
end
