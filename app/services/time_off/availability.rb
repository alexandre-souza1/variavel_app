module TimeOff
  class Availability
    def initialize(schedule:, first:, last: first, memberships: nil)
      @schedule = schedule
      members = (memberships || schedule.time_off_memberships).during(first, last).pluck(:id)
      @overrides = TimeOffOverride.where(time_off_membership_id: members, date: first..last).index_by { |o| [o.time_off_membership_id, o.date] }
      vacations = schedule.time_off_vacations.active.during(first, last)
      vacations = vacations.where(time_off_membership_id: memberships.select(:id)) if memberships
      @vacations = vacations.includes(time_off_membership: [:driver, :ajudante]).group_by(&:person_key)
    end

    def vacation(member, date)
      (@vacations[member.person_key] || []).find { |v| v.covers?(date) }
    end

    def override(member, date)
      @overrides[[member.id, date]]
    end

    def status(member, date)
      return unless member.active_person?(date)
      base = @schedule.base_status(member, date)
      return unless base
      return 'vacation' if vacation(member, date)
      override(member, date)&.status || base
    end
  end
end
