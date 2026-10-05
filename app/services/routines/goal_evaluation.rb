module Routines
  class GoalEvaluation
    def self.call(indicator:, value:, goal:)
      return if value.blank? || goal.blank? || indicator.manual_calculation?

      result = comparable_value(indicator, value)
      target = comparable_value(indicator, goal)
      return if result.nil? || target.nil?

      achieved = indicator.less_or_equal? ? result <= target : result >= target
      achieved ? :success : :danger
    end

    def self.comparable_value(indicator, value)
      case indicator.value_type
      when "integer", "decimal", "percentage", "currency"
        BigDecimal(value.to_s.tr(",", "."))
      when "date"
        Date.iso8601(value.to_s)
      when "time"
        match = value.to_s.match(/\A([01]\d|2[0-3]):([0-5]\d)\z/)
        (match[1].to_i * 60) + match[2].to_i if match
      when "duration"
        match = value.to_s.tr(".", ":").match(/\A(\d+):([0-5]\d)\z/)
        (match[1].to_i * 60) + match[2].to_i if match
      when "boolean"
        return 1 if value.to_s.in?(%w[true 1])
        return 0 if value.to_s.in?(%w[false 0])
      else
        value.to_s
      end
    rescue ArgumentError
      nil
    end
    private_class_method :comparable_value
  end
end
