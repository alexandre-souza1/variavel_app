module AiAssistant
  module QuerySupport
    private

    def query_date(value, default: Date.current)
      date = value.present? ? Date.iso8601(value.to_s) : default
      raise ArgumentError unless (2000..2100).cover?(date.year)
      date
    end

    def query_month(value, default: Date.current)
      return default.beginning_of_month if value.blank?
      raise ArgumentError unless value.to_s.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)
      query_date("#{value}-01")
    end

    def date_range(args, default_from: Date.current.beginning_of_month, default_to: Date.current.end_of_month)
      first = query_date(args['from'], default: default_from)
      last = query_date(args['to'], default: default_to)
      raise ArgumentError if first > last || (last - first).to_i > 366
      [first, last]
    end

    def closing_range(args, sector: 'du')
      closing_day = sector == 'az' ? 18 : 20
      current = Date.current.day > closing_day ? Date.current.next_month : Date.current
      month = query_month(args['month'], default: current)
      last = month.change(day: closing_day)
      date_range(args, default_from: last.prev_month.change(day: closing_day + 1), default_to: last)
    end

    def array_page(records, args)
      current = Integer(args.fetch('page', 1)).clamp(1, 500)
      { total: records.size, page: current, has_more: records.size > current * 20,
        records: records.slice((current - 1) * 20, 20).to_a }
    end

    def filter_status(scope, value, active: :active, archived: :archived)
      case value.presence || 'active'
      when 'active' then scope.public_send(active)
      when 'archived' then scope.public_send(archived)
      when 'all' then scope
      else raise ArgumentError
      end
    end

    def employee_sector(args, required: false)
      sector = args['sector'].presence
      raise ArgumentError if sector && !%w[du az].include?(sector)
      raise ActiveRecord::RecordNotFound if sector && !@access.employee_sectors.include?(sector)
      return sector if sector
      return @access.employee_sectors.first if @access.employee_sectors.one?
      raise ArgumentError if required
    end

    def finance_scope(args)
      scope = @access.invoices
      if args['sector'].present?
        value = args['sector'].to_s
        sector = BudgetCategory.sectors.key(value) || (BudgetCategory.sectors.key?(value) && value)
        raise ArgumentError unless sector
        scope = scope.joins(:budget_category).where(budget_categories: { sector: sector })
      end
      scope
    end

    def checklist_scope
      @user.admin? || @user.supervisor? ? Checklist.all : @user.checklists
    end

    def bounded_text(value, limit = 2000)
      value.to_s.truncate(limit)
    end
  end
end
