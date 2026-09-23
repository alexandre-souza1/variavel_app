class ConsolidateLinkedClosingsByPeriod < ActiveRecord::Migration[7.1]
  class CareerEvent < ActiveRecord::Base
    self.table_name = 'employee_career_events'
  end

  class Closing < ActiveRecord::Base
    self.table_name = 'variable_closings'
  end

  def up
    CareerEvent.where("details ->> 'action' = ?", 'link_record').find_each do |event|
      source_id = event.details.to_h.dig('source', 'id').to_i
      next if source_id.zero? || source_id == event.employee_id

      consolidate_event(event, source_id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Os fechamentos consolidados devem permanecer disponíveis.'
  end

  private

  def consolidate_event(event, source_id)
    destination_records = Closing.where(employee_id: event.employee_id).to_a
    source_records = Closing.where(employee_id: [event.employee_id, source_id]).to_a
      .select { |closing| closing.result.to_h.dig('employee', 'id').to_i == source_id }
    destination_records = destination_records.select { |closing| closing.result.to_h.dig('employee', 'id').to_i == event.employee_id }

    destination_by_period = destination_records.group_by { |closing| [closing.year, closing.month] }
      .transform_values { |closings| closings.max_by(&:revision) }
    source_by_period = source_records.group_by { |closing| [closing.year, closing.month] }
      .transform_values { |closings| closings.max_by(&:revision) }
    consolidated = []

    (destination_by_period.keys & source_by_period.keys).each do |period|
      destination = destination_by_period.fetch(period)
      source = source_by_period.fetch(period)
      next if destination.result.to_h['consolidated_from'].present? || source.result.to_h['consolidated_from'].present?

      user_id = destination.user_id || source.user_id || select_value('SELECT id FROM users ORDER BY id LIMIT 1')
      next unless user_id

      revision = Closing.where(employee_id: event.employee_id, year: period[0], month: period[1]).maximum(:revision).to_i + 1
      combined = VariableClosing.merge_results(destination.result, source.result, employee: Employee.find(event.employee_id))
      combined['consolidated_from'] = [destination.id, source.id]
      consolidated_closing = Closing.create!(employee_id: event.employee_id, user_id: user_id, year: period[0], month: period[1],
        revision: revision, reason: 'Mesclagem de variáveis de cadastros vinculados', result: combined,
        legacy_baseline: false, created_at: Time.current, updated_at: Time.current)
      consolidated << { 'destination_closing_id' => destination.id, 'source_closing_id' => source.id,
                        'consolidated_closing_id' => consolidated_closing.id, 'year' => period[0], 'month' => period[1] }
    end

    return if consolidated.empty?

    details = event.details.to_h
    details['consolidated_closings'] = consolidated
    CareerEvent.where(id: event.id).update_all(details: details, updated_at: Time.current)
  end
end
