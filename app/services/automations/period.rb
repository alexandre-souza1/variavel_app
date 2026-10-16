module Automations
  class Period
    LABELS = { "today" => "Hoje", "yesterday" => "Ontem", "week" => "Semana atual", "last_week" => "Semana anterior", "month" => "Mês atual", "last_month" => "Mês anterior", "all" => "Todo o histórico" }.freeze
    attr_reader :start_date, :end_date, :frequency, :anchor

    def initialize(key, now: Time.current)
      today = now.to_date
      @start_date, @end_date, @frequency = case key
      when "today" then [today, today, "daily"]
      when "yesterday" then [today - 1, today - 1, "daily"]
      when "week" then [today.beginning_of_week, today, "weekly"]
      when "last_week" then [(today - 1.week).beginning_of_week, (today - 1.week).end_of_week, "weekly"]
      when "month" then [today.beginning_of_month, today, "monthly"]
      when "last_month" then [today.prev_month.beginning_of_month, today.prev_month.end_of_month, "monthly"]
      when "all" then [nil, today, nil]
      else raise Invalid, "Período indisponível."
      end
      @anchor = @end_date
    end

    def date_range = start_date..end_date
    def time_range = start_date&.in_time_zone&.beginning_of_day..end_date.in_time_zone.end_of_day
    # Stable within a calendar period even when the current total changes daily.
    def effect_key
      [frequency || "all", start_date&.iso8601].join(":")
    end

    def include_reference?(date)
      case frequency
      when "daily" then date == anchor
      when "weekly" then date.beginning_of_week == anchor.beginning_of_week
      when "monthly" then date.beginning_of_month == anchor.beginning_of_month
      end
    end
  end
end
