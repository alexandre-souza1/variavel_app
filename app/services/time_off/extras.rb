module TimeOff
  class Extras
    attr_reader :rows

    def initialize(schedule:, month:, members:, availability:)
      dates = (month.beginning_of_month..month.end_of_month)
      @rows = members.group_by(&:person_key).map do |key, memberships|
        days = dates.select do |date|
          member = memberships.find { |m| m.covers?(date) }
          member && schedule.base_status(member, date) == 'off' && availability.status(member, date) == 'working'
        end
        { key: key, member: memberships.max_by(&:starts_on), dates: days }
      end.sort_by { |row| [-row[:dates].size, row[:member].person.nome] }
      @days = rows.index_by { |row| row[:key] }
    end

    def dates(member)
      @days[member.person_key]&.fetch(:dates) || []
    end
  end
end
