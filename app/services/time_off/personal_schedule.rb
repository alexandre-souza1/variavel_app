module TimeOff
  # Read-only view shared by the employee portal and the identified public chat.
  # Missing enrollment means unknown availability, never presumed work or rest.
  class PersonalSchedule
    REST_STATUSES = %w[off dsr].freeze

    def initialize(person:, today: Date.current, month: nil)
      @person = person
      @today = today
      @month = calendar_month(month)
      @week_start = today.beginning_of_week(:monday)
      @search_end = today + 365
    end

    def call
      load_availability
      upcoming = (@today..@search_end).lazy.map { |date| day(date) }
      {
        available: @members.any?, today: @today, month: @month,
        week_start: @week_start, week_end: @week_start + 6,
        week: (@week_start..@week_start + 6).map { |date| day(date) },
        days: (@month..@month.end_of_month).map { |date| day(date) },
        next_off: upcoming.find { |entry| REST_STATUSES.include?(entry[:status]) },
        next_group_off: upcoming.find { |entry| entry[:status] == 'off' },
        searched_until: @search_end,
        period_definition: 'Semana de segunda a domingo e mês de calendário. Folga e DSR são descansos; férias e indisponibilidade são situações distintas. A próxima folga considera hoje, trocas individuais e férias cadastradas.'
      }
    end

    private

    def calendar_month(value)
      return @today.beginning_of_month unless value.to_s.match?(/\A[0-9]{4}-(0[1-9]|1[0-2])\z/)

      parsed = Date.strptime(value, '%Y-%m').beginning_of_month
      parsed.year.positive? ? parsed : @today.beginning_of_month
    rescue Date::Error
      @today.beginning_of_month
    end

    def load_availability
      @members = []
      return unless @person.is_a?(Employee) || @person.is_a?(Driver) || @person.is_a?(Ajudante)
      return unless @person.persisted?
      active = @person.is_a?(Employee) ? @person.active? : People.active?(@person)
      return unless active

      @schedule = TimeOffSchedule.order(:id).first
      return unless @schedule

      employee = @person.is_a?(Employee) ? @person : @person.employee
      scope = @schedule.time_off_memberships.with_active_people
      scope = if employee
                scope.where(employee_id: employee.id)
                  .or(scope.where(driver_id: Driver.where(employee_id: employee.id).select(:id)))
                  .or(scope.where(ajudante_id: Ajudante.where(employee_id: employee.id).select(:id)))
              elsif @person.is_a?(Driver)
                scope.where(driver_id: @person.id)
              else
                scope.where(ajudante_id: @person.id)
              end
      first = [@week_start, @month].min
      last = [@search_end, @month.end_of_month].max
      @members = scope.during(first, last).includes(driver: :employee, ajudante: :employee).order(:starts_on).to_a
      return if @members.empty?

      @availability = Availability.new(schedule: @schedule, first: first, last: last, memberships: scope)
    end

    def day(date)
      member = @members.find { |entry| entry.covers?(date) }
      status = @availability&.status(member, date) if member
      {
        date: date, weekday: I18n.t('date.day_names')[date.wday],
        status: status, label: TimeOffSchedule::STATUSES[status] || 'Sem escala',
        group: status && member.group_code,
        adjusted: status.present? && @availability.override(member, date).present?
      }
    end
  end
end
