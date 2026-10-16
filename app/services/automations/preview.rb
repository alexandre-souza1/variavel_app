module Automations
  class Preview
    def self.call(rule, now: Time.current)
      raise Invalid, rule.errors.full_messages.to_sentence unless rule.valid?
      period = Period.new(rule.period, now: now)
      result = Catalog::SOURCES.fetch(rule.source_key)[:adapter].call(rule, period: period, now: now)
      destination = Catalog::ACTIONS.fetch(rule.action_key)[:adapter].preview(rule, period: period, result: result)
      { period: period, result: result, destination: destination, condition_met: rule.condition_met?(result[:value]) }
    end
  end
end
