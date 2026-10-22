module ChecklistTracking
  class Report
    attr_reader :year, :rows, :events, :monthly_counts

    def initialize(scope:, year:)
      @year = year
      records = scope.active.where(occurred_on: Date.new(year, 1, 1)..Date.new(year, 12, 31))
        .includes(:employee, :recorded_by, task: [:users, { bucket: :action_plan }, { routine_value: :routine }]).to_a
      # Several actions may investigate the same missed checklist.
      @events = records.group_by { |record| [record.employee_id, record.occurred_on, record.checklist_kind] }.map do |_, sources|
        { employee: sources.first.employee, date: sources.first.occurred_on,
          kind: sources.first.kind_label, sources: sources.sort_by(&:id),
          completed: sources.all? { |source| source.task.completed? } }
      end.sort_by { |event| [-event[:date].jd, event[:employee].nome] }
      @monthly_counts = (1..12).map { |month| events.count { |event| event[:date].month == month } }
      @rows = events.group_by { |event| event[:employee] }.map do |employee, employee_events|
        { employee: employee, total: employee_events.size,
          months: (1..12).map { |month| employee_events.count { |event| event[:date].month == month } },
          last_date: employee_events.first[:date] }
      end.sort_by { |row| [-row[:total], row[:employee].nome] }
    end

    def total
      events.size
    end

    def recurring_count
      rows.count { |row| row[:total] > 1 }
    end

    def pending_count
      events.count { |event| !event[:completed] }
    end
  end
end
