module ChecklistTracking
  class Report
    attr_reader :year, :rows, :events, :monthly_counts

    def initialize(scope:, year:, employees: nil)
      @year = year
      records = scope.active.where(occurred_on: Date.new(year, 1, 1)..Date.new(year, 12, 31))
        .includes(:task, employee: :employee_roles).to_a.reject { |record| record.role_restriction_reason.present? }
      # Several actions may investigate the same missed checklist.
      @events = records.group_by { |record| [record.subject_key, record.occurred_on, record.checklist_kind] }.map do |_, sources|
        { employee: sources.first.employee, spot_plate: sources.first.spot_plate, subject_key: sources.first.subject_key, name: sources.first.subject_name, date: sources.first.occurred_on,
          kind: sources.first.kind_label, sources: sources.sort_by(&:id),
          completed: sources.all? { |source| source.task.completed? } }
      end.sort_by { |event| [-event[:date].jd, event[:name]] }
      @monthly_counts = (1..12).map { |month| events.count { |event| event[:date].month == month } }
      @rows = events.group_by { |event| event[:subject_key] }.map do |_, employee_events|
        { employee: employee_events.first[:employee], spot_plate: employee_events.first[:spot_plate], name: employee_events.first[:name], total: employee_events.size,
          months: (1..12).map { |month| employee_events.count { |event| event[:date].month == month } },
          last_date: employee_events.first[:date] }
      end
      if employees
        recorded_ids = @rows.filter_map { |row| row[:employee]&.id }.to_set
        employees.each do |employee|
          next if recorded_ids.include?(employee.id)
          @rows << { employee: employee, spot_plate: nil, name: employee.nome, total: 0, months: [0] * 12, last_date: nil }
        end
      end
      @rows.sort_by! { |row| [-row[:total], row[:name]] }
    end

    def total
      events.size
    end

    def recurring_count
      rows.count { |row| row[:total] > 1 }
    end

    def recorded_subject_count
      rows.count { |row| row[:total].positive? }
    end

    def pending_count
      events.count { |event| !event[:completed] }
    end
  end
end
