require "test_helper"

class MapaTest < ActiveSupport::TestCase
  test 'cargo override for a legacy map is audited and can be cleared' do
    mapa = Mapa.create!(mapa: 'LEGACY-OVERRIDE', data: '01/09/2026', matric_motorista: 'MAP-1', fator: 0,
      cx_real: 10, pdv_real: 5, pdv_total: 5, recarga: 'NAO')

    mapa.apply_cargo_override!(cargo: 'van', reason: 'Cargo do legado conferido pelo RH', user: users(:one))
    assert_equal 'van', mapa.reload.cargo_override
    assert_equal 'Cargo do legado conferido pelo RH', mapa.cargo_override_reason
    assert_equal users(:one), mapa.cargo_override_user
    assert_equal({ previous_cargo: nil, cargo: 'van', reason: 'Cargo do legado conferido pelo RH' },
      mapa.mapa_cargo_overrides.order(:id).last.slice(:previous_cargo, :cargo, :reason).symbolize_keys)

    mapa.apply_cargo_override!(cargo: nil, reason: 'Retorno ao cargo calculado pelo histórico', user: users(:one))
    assert_nil mapa.reload.cargo_override
    assert_equal 2, mapa.mapa_cargo_overrides.count
    assert_equal 'van', mapa.mapa_cargo_overrides.order(:id).last.previous_cargo
  end

  test 'cargo override requires a reason when it changes the applied cargo' do
    mapa = mapas(:one)
    assert_raises(ActiveRecord::RecordInvalid) do
      mapa.apply_cargo_override!(cargo: 'motorista', reason: '', user: users(:one))
    end
    assert_nil mapa.reload.cargo_override
  end
end
