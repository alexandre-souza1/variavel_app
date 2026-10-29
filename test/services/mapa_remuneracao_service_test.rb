require 'test_helper'

class MapaRemuneracaoServiceTest < ActiveSupport::TestCase
  setup do
    %w[motorista ajudante van].each do |cargo|
      { 'valor_caixa' => 1, 'valor_entrega' => 2, 'valor_recarga' => 80 }.each do |name, value|
        CalculationRateVersion.create!(categoria: cargo, nome: name, valor: value)
      end
    end
    CalculationRateVersion.create!(categoria: 'geral', nome: 'bonus_devolucao', valor: 100)
    CalculationRateVersion.create!(categoria: 'geral', nome: 'bonus_devolucao', valor: 999, effective_on: '2026-09-15')
  end

  test 'AS produces no route remuneration for any role even when marked as a refill' do
    %w[motorista ajudante van].each do |cargo|
      service = MapaRemuneracaoService.new(cargo)
      %w[NAO SIM].each do |refill|
        values = service.values(map(entrega: 'AS', recarga: refill))
        %i[valor_cx valor_pdv valor_rec valor_mp].each { |key| assert_equal 0, values[key] }
        assert_not values[:recarga]
        assert_equal service.totals([]), service.totals([map(entrega: 'AS', recarga: refill)])
      end
    end
  end

  test 'AS cannot complete the minimum map count or alter production devolution refills and bonus date' do
    %w[motorista ajudante van].each do |cargo|
      service = MapaRemuneracaoService.new(cargo)
      route_maps = Array.new(14) { map }
      as_maps = [map(entrega: 'AS', data: '20/09/2026', pdv_total: 1000, pdv_real: 0), map(entrega: 'AS', recarga: 'SIM')]

      totals = service.totals(route_maps + as_maps)
      assert_equal service.totals(route_maps), totals
      assert_equal 14, totals[:quantidade_mapas]
      assert_equal 0, totals[:bonus_devolucao]

      route_maps << map
      totals = service.totals(route_maps + as_maps)
      assert_equal service.totals(route_maps), totals
      assert_equal 15, totals[:quantidade_mapas]
      assert_equal 100, totals[:bonus_devolucao]
      assert_equal 400, totals[:valor_total]
    end
  end

  private

  def map(**attributes)
    Mapa.new({ data: '10/09/2026', fator: 1, cx_real: 10, pdv_total: 5, pdv_real: 5, recarga: 'NAO' }.merge(attributes))
  end
end
