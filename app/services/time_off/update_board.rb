module TimeOff
  class UpdateBoard
    def self.call(schedule:, date:, attributes:, user:)
      attributes = attributes.to_h.deep_stringify_keys
      schedule.with_lock do
        current = Coverage.new(schedule: schedule, date: date)
        raise UpdateDay::InvalidChange, 'Defina o dimensionamento para um dia de operação da escala.' unless current.editable?
        raise UpdateDay::Conflict, 'O dimensionamento mudou. Atualize o painel antes de salvar.' unless current.signature == attributes['dimensioning_signature']
        previous_cars = Board.new(current).cars.deep_dup
        changes = Array(attributes['statuses'])
        raise UpdateDay::InvalidChange, 'Um colaborador possui situações repetidas.' unless changes.map { |c| c['member_id'].to_s }.uniq.size == changes.size
        changes.each do |change|
          member = current.members.find { |m| m.id == change['member_id'].to_i }
          raise UpdateDay::InvalidChange, 'Colaborador não pertence à escala nesta data.' unless member
          UpdateDay.call(schedule: schedule, membership_id: member.id, date: date, status: change['status'],
            reason: attributes['reason'], expected_revision: change['expected_revision'], user: user)
        end
        proposed = Coverage.new(schedule: schedule, date: date)
        routing = attributes['routing_token'].present? ? RoutingCsv.verify(attributes['routing_token'], schedule: schedule, date: date) : current.details['routing_import']
        proposed.details['routing_import'] = routing if routing
        cars = Board.validate!(proposed, attributes['cars'])
        routes = cars.select { |c| c['operation'] == 'route' }
        special = Coverage::SPECIAL_OPERATIONS.index_with do |operation|
          subset = cars.select { |c| c['operation'] == operation }.sort_by { |c| c['position'] }
          assignments = { 'driver' => subset.map { |c| c['driver'] } }
          assignments['helper'] = subset.map { |c| c['helper1'] } if operation == 'vespertina'
          assignments
        end
        helper_drivers = routes.flat_map { |c| [c['helper1'], c['helper2']] }.compact.select { |id| proposed.member(id).role == 'driver' }
        UpdateCoverage.call(schedule: schedule, date: date, user: user, attributes: attributes.slice('reason', 'expected_revision', 'dimensioning_signature').merge(
          'solo_routes' => routes.count { |c| c['helper_count'].zero? },
          'double_helper_routes' => routes.count { |c| c['helper_count'] == 2 },
          'helper_driver_ids' => helper_drivers, 'special_assignments' => special, 'cars' => cars, 'previous_cars' => previous_cars, 'routing_import' => routing))
      end
    end
  end
end
