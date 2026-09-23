require 'test_helper'

class PublicVariableConsumptionContextTest < ActiveSupport::TestCase
  setup do
    @previous_url_options = Rails.application.routes.default_url_options.dup
    Rails.application.routes.default_url_options[:host] = "example.test"
    @employee = Employee.create!(nome: 'Motorista IA', matricula: 'IA-FUEL')
    @employee.employee_roles.create!(cargo: 'motorista', promax: 'IA-FUEL', starts_on: '2026-01-01', reason: 'Admissão')
    @identity = PublicVariableIdentity.new('colaborador', @employee)
    GasolaSupply.create!(external_id: 'ia-fuel', registration: 'IA-FUEL', plate: 'ABC-1234',
      concluded_at: Time.zone.local(2026, 9, 10), fuel: 'dieselS10', category: 'veículo', status: 'CONCLUDED',
      liters: 100, distance: 300, goal: 4)
    GasolaSupply.create!(external_id: 'ia-other', registration: 'OTHER', plate: 'PRIVATE-PLATE',
      concluded_at: Time.zone.local(2026, 9, 10), fuel: 'dieselS10', category: 'veículo', status: 'CONCLUDED',
      liters: 100, distance: 900, goal: 4)
  end

  teardown { Rails.application.routes.default_url_options.replace(@previous_url_options) }

  test 'context uses identified registration despite question mentioning someone else' do
    context = PublicVariableContext.new(@identity, question: 'Consumo da matrícula OTHER', selected_period: '2026-09').call
    fuel = context[:fuel_consumption]
    assert_equal '2026-09', fuel[:selected_period]
    totals = fuel[:monthly]['2026-09']
    assert_equal 3.0, totals[:average_km_per_liter]
    assert_equal 4.0, totals[:goal_km_per_liter]
    assert_equal false, totals[:achieved]
    assert_equal '2026-08-21', totals[:from]
    assert_equal '2026-09-20', totals[:to]
    assert_equal false, totals[:complete]
    assert_includes fuel[:economical_driving_lup], '/downloads/232/open'
    refute_includes fuel.to_json, 'PRIVATE-PLATE'
  end

  test 'empty period and missing goal remain unknown instead of zero' do
    GasolaSupply.find_by!(external_id: 'ia-fuel').update!(goal: nil)
    fuel = PublicVariableContext.new(@identity, selected_period: '2026-07').send(:fuel_consumption_context)
    assert_nil fuel[:monthly]['2026-07'][:average_km_per_liter]
    assert_nil fuel[:monthly]['2026-07'][:achieved]
    assert_nil fuel[:monthly]['2026-09'][:goal_km_per_liter]
    assert_nil fuel[:monthly]['2026-09'][:achieved]
  end

  test 'helper has no driver consumption context' do
    @employee.employee_roles.update_all(cargo: 'ajudante')
    assert_nil PublicVariableContext.new(@identity).send(:fuel_consumption_context)
  end
end
