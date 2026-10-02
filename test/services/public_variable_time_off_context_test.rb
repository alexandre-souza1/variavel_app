require 'test_helper'

class PublicVariableTimeOffContextTest < ActiveSupport::TestCase
  setup do
    @previous_url_options = Rails.application.routes.default_url_options.dup
    Rails.application.routes.default_url_options[:host] = 'example.test'
    @identity = PublicVariableIdentity.new('motorista', drivers(:one))
    @schedule = TimeOffSchedule.create!(name: 'Piloto', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @member = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'A', starts_on: @schedule.starts_on)
    other = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'E', starts_on: @schedule.starts_on)
    other.time_off_overrides.create!(date: '2026-10-03', status: 'unavailable', reason: 'Motivo confidencial de outra pessoa')
  end

  teardown { Rails.application.routes.default_url_options.replace(@previous_url_options) }

  test 'AI receives only identified schedule even when asked for another employee' do
    travel_to Time.zone.local(2026, 10, 2) do
      context = PublicVariableContext.new(@identity, question: 'Qual a folga do ajudante?').call[:time_off]
      assert_equal Date.new(2026, 10, 6), context[:next_group_off][:date]
      assert_equal ['A'], context[:days].filter_map { |day| day[:group] }.uniq
      refute_includes context.to_json, 'unavailable'
      refute_includes context.to_json, 'Motivo confidencial'
      @member.time_off_overrides.create!(date: '2026-10-06', status: 'working', reason: 'Extra')
      assert_equal Date.new(2026, 10, 14), PublicVariableContext.new(@identity).call[:time_off][:next_group_off][:date]
    end
  end

  test 'Gemini prompt includes real dates and explicit missing schedule handling' do
    travel_to Time.zone.local(2026, 10, 2) do
      service = PublicVariableChatService.new(identity: @identity, history: [], question: 'Quando é minha próxima folga?')
      prompt = service.send(:prompt)
      context = JSON.parse(prompt.split("CONTEXTO DE DADOS:\n", 2).last.split("\n\nPERGUNTA ATUAL:", 2).first)
      assert_equal '2026-10-04', context.dig('time_off', 'next_off', 'date')
      assert_equal 'dsr', context.dig('time_off', 'next_off', 'status')
      assert_includes prompt, 'não há escala cadastrada disponível'
      @member.destroy!
      assert_not PublicVariableContext.new(@identity).call[:time_off][:available]
    end
  end
end
