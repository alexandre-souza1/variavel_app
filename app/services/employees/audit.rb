module Employees
  # Read-only reconciliation report. Names and document values are deliberately
  # omitted; the RH ficha contains the data needed to review each identifier.
  class Audit
    def self.call
      people = Employee.with_career_history.includes(:employee_roles, :employee_names).to_a
      duplicate_registrations = people.group_by(&:matricula).values.select { |group| group.size > 1 }.map { |group| group.map(&:id) }
      ambiguous_names = EmployeeName.where(employee_id: people.map(&:id)).group(:normalized_name)
        .having('COUNT(DISTINCT employee_id) > 1').count.size
      overlapping_registrations = people.flat_map { |person| person.registration_aliases.map { |key| [key, person.id] } }
        .group_by(&:first).values.map { |entries| entries.map(&:last).uniq }.select { |ids| ids.size > 1 }
      identities = people.index_by(&:id)
      mismatches = Registry::MODELS.flat_map do |model|
        model.where(employee_id: identities.keys).filter_map do |record|
          person = identities.fetch(record.employee_id)
          fields = Registry::IDENTITY_FIELDS.select { |field| record[field] != person[field] }
          { model: model.name, record_id: record.id, employee_id: person.id, fields: fields } if fields.any?
        end
      end
      unresolved_sources = [AzRvPoint, AzRvTask, AzRvOnDemandActivity].to_h do |model|
        rows = model.where(employee_id: nil).pluck(:id, :employee_key)
        resolutions = EmployeeName.resolutions(rows.map(&:last).uniq)
        ids = rows.filter_map { |id, key| id unless resolutions[key] }
        [model.name, { count: ids.size, sample_ids: ids.first(20) }]
      end
      {
        missing_start_dates: EmployeeRole.where(starts_on: nil).pluck(:employee_id, :id),
        missing_az_shifts: EmployeeRole.az.where(turno: nil).pluck(:employee_id, :id),
        duplicate_registrations: duplicate_registrations, overlapping_registration_aliases: overlapping_registrations,
        ambiguous_exact_names: ambiguous_names,
        identity_mismatches: mismatches, unresolved_az_sources: unresolved_sources
      }
    end
  end
end
