class MergeLinkedEmployeeClosings < ActiveRecord::Migration[7.1]
  class CareerEvent < ActiveRecord::Base
    self.table_name = 'employee_career_events'
  end

  class Closing < ActiveRecord::Base
    self.table_name = 'variable_closings'
  end

  def up
    CareerEvent.where("details ->> 'action' = ?", 'link_record').find_each do |event|
      source = event.details.to_h['source'].to_h
      source_id = source['id'].to_i
      next if source_id.zero? || source_id == event.employee_id

      merge_closings(event, source_id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Os fechamentos mesclados devem permanecer no cadastro principal.'
  end

  private

  def merge_closings(event, source_id)
    used_revisions = Hash.new { |hash, period| hash[period] = [] }
    Closing.where(employee_id: event.employee_id).find_each do |closing|
      used_revisions[[closing.year, closing.month]] << closing.revision
    end

    moved = []
    Closing.where(employee_id: source_id).order(:year, :month, :revision, :id).find_each do |closing|
      period = [closing.year, closing.month]
      revision = closing.revision
      revision = used_revisions[period].max + 1 if used_revisions[period].include?(revision)
      Closing.where(id: closing.id).update_all(employee_id: event.employee_id, revision: revision, updated_at: Time.current)
      used_revisions[period] << revision
      moved << { 'closing_id' => closing.id, 'year' => closing.year, 'month' => closing.month,
                 'original_revision' => closing.revision, 'revision' => revision }
    end

    return if moved.empty?

    details = event.details.to_h
    details['merged_closings'] = moved
    CareerEvent.where(id: event.id).update_all(details: details, updated_at: Time.current)
  end
end
