require 'test_helper'

class PublicVariableAsContextTest < ActiveSupport::TestCase
  test 'legacy variable context ignores AS maps in amounts days and available periods' do
    travel_to Time.zone.local(2026, 10, 29) do
      { 'motorista' => drivers(:one), 'ajudante' => ajudantes(:one) }.each do |profile, person|
        person.update!(promax: "CONTEXT-AS-#{profile}")
        scope_attribute = profile == 'motorista' ? :matric_motorista : :matric_ajudante
        [['Rota', '10/09/2026'], ['AS', '11/09/2026'], ['AS', '10/10/2026']].each do |delivery, date|
          Mapa.create!({ mapa: "CONTEXT-#{profile}-#{date}", entrega: delivery, data: date,
            fator: 1, cx_real: 10, pdv_total: 5, pdv_real: 5 }.merge(scope_attribute => person.promax))
        end

        identity = PublicVariableIdentity.new(profile, person)
        context = PublicVariableContext.new(identity).send(:du_context, Mapa.where(scope_attribute => person.promax))
        assert_equal ['2026-09'], context[:monthly].keys
        assert_equal 1, context[:monthly]['2026-09'][:days]
        assert_equal ['2026-09-10'], context[:recent_daily].keys
      end
    end
  end
end
