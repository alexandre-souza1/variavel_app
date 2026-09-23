require "test_helper"

class AzHelperEfcServiceTest < ActiveSupport::TestCase
  test "counts EFC once per achieved day within the cycle and ignores EFD and TMA" do
    AzMapa.delete_all
    create_map("2026-09-13", true)
    create_map("2026-08-18", true)
    create_map("2026-08-19", true)
    create_map("2026-09-18", true, turno: [0])
    create_map("2026-09-18", true, turno: [2])
    create_map("2026-09-17", false)
    create_map("2026-09-19", true)
    create_map("2026-09-16", true, tipo: :eficiencia_descarga, turno: [1])
    create_map("2026-09-15", true, tipo: :tempo_atendimento)

    service = AzHelperEfcService.new(start_date: Date.new(2026, 8, 19), end_date: Date.new(2026, 9, 18))
    assert_equal [Date.new(2026, 8, 19), Date.new(2026, 9, 18)], service.daily_values.keys
    assert_equal BigDecimal("10"), service.total
    assert_equal 0, AzHelperEfcService.new(start_date: Date.new(2027, 1, 1), end_date: Date.new(2027, 1, 18)).total
  end

  test "dashboard and chat include EFC for all helper shifts without other activities" do
    AzMapa.delete_all
    create_map("2026-09-13", true)
    create_map("2026-09-18", true)
    create_map("2026-09-17", false)
    create_map("2026-09-16", true, tipo: :eficiencia_descarga, turno: [1])
    helper = az_ajudantes(:one)
    helper.update!(nome: "Ajudante EFC", active: true)

    travel_to Time.zone.local(2026, 9, 23) do
      [0, 1, 2].each do |shift|
        helper.update!(turno: shift)
        dashboard = AzDashboardService.new(start_date: Date.new(2026, 8, 19), end_date: Date.new(2026, 9, 18), turno: shift).call
        row = dashboard.helpers.find { |item| item[:person].id == helper.id }
        assert_equal 1, row[:efc_days]
        assert_equal BigDecimal("5"), row[:efc_value]
        assert_equal BigDecimal("5"), row[:total]

        identity = Struct.new(:record).new(helper)
        context = PublicVariableContext.new(identity).send(:az_helper_context)
        assert_equal 5.0, context[:monthly].fetch("2026-09")[:efc]
        assert_equal 5.0, context[:monthly].fetch("2026-09")[:total]
      end
    end
  end

  test "operator dashboard and chat exclude Sunday EFC while preserving EFD and TMA" do
    AzMapa.delete_all
    create_map("2026-09-12", true)
    create_map("2026-09-13", true)
    create_map("2026-09-13", true, tipo: :eficiencia_descarga, turno: [1])
    create_map("2026-09-13", true, tipo: :tempo_atendimento, turno: [0, 1, 2])
    operator = operators(:one)
    operator.update!(active: true)
    { "valor_efc" => 12, "valor_tma" => 2 }.each do |name, value|
      rate = ParametroCalculo.find_or_initialize_by(categoria: "operador", nome: name)
      rate.update!(valor: value)
    end
    travel_to Time.zone.local(2026, 9, 23) do
      [0, 1, 2].each do |shift|
        operator.update!(turno: shift)
        dashboard = AzDashboardService.new(start_date: Date.new(2026, 9, 12), end_date: Date.new(2026, 9, 13), turno: shift).call
        row = dashboard.operators.find { |item| item[:person].id == operator.id }
        assert_equal 1, row[:efficiency]
        assert_equal 12, row[:efficiency_value]
        assert_equal 2, row[:tma_value]
        indicator = dashboard.indicators.find { |item| item[:type] == "eficiencia_carregamento" }
        assert_equal(shift == 1 ? 0 : 1, indicator[:count])
        identity = Struct.new(:record).new(operator)
        month = PublicVariableContext.new(identity).send(:operator_context)[:monthly].fetch("2026-09")
        assert_equal 12, month[:efficiency]
        assert_equal 2, month[:tma]
      end
    end
  end

  private

  def create_map(date, achieved, tipo: :eficiencia_carregamento, turno: [0, 2])
    AzMapa.create!(data: date, tipo: tipo, turno: turno, resultado: 95, atingiu_meta: achieved)
  end
end
