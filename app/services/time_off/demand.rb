module TimeOff
  class Demand
    def initialize(coverage)
      @coverage = coverage
    end

    def metrics
      plan = PcdPlan.find_by(date: @coverage.date)
      cars = plan ? Pcd::Board.new(date: @coverage.date, plan: plan).cars.reject { |c| c['freight'] } : Board.new(@coverage).cars
      scheduled = cars.select { |c| c['scheduled'] }
      members = @coverage.members.uniq(&:person_key).select { |m| @coverage.available?(m) }
      acting_helpers = plan ? scheduled.flat_map { |c| [c['helper1'], c['helper2']] }.compact.grep(/\Adriver:/).uniq : []
      drivers = members.count { |m| %w[motorista van].include?(m.cargo_on(@coverage.date)) && !acting_helpers.include?("driver:#{m.person.id}") }
      helpers = members.count { |m| m.cargo_on(@coverage.date) == 'ajudante' } + members.count { |m| %w[motorista van].include?(m.cargo_on(@coverage.date)) && acting_helpers.include?("driver:#{m.person.id}") }
      helper_need = scheduled.sum { |c| c['helper_count'] }
      van_gap = [scheduled.count { |c| c['operation'] == 'van' } - members.count { |m| m.cargo_on(@coverage.date) == 'van' && !acting_helpers.include?("driver:#{m.person.id}") }, 0].max
      { cars: scheduled.size, dimensioned_cars: @coverage.quantities.values.sum, drivers: drivers, helpers: helpers,
        driver_gap: [scheduled.size - drivers, van_gap, 0].max, helper_gap: [helper_need - helpers, 0].max, van_gap: van_gap,
        helper_need: helper_need, from_pcd: plan.present? }
    end
  end
end
