module ChecklistTracking
  class AutomaticRegistration
    Result = Struct.new(:created, :pending, :preserved, keyword_init: true)

    def initialize(user:, tasks:, year:, employee_sector: nil, subject: "employees")
      @user, @tasks, @year, @employee_sector, @subject = user, tasks, year, employee_sector, subject
    end

    def call
      result = Result.new(created: 0, pending: 0, preserved: 0)
      return result unless @user.can_view_checklist_tracking?
      employees = Employee.for_checklist_tracking(@user).includes(:employee_names, :employee_roles).to_a
      return result if @employee_sector && !@user.employee_sectors.include?(@employee_sector)
      selected_ids = @employee_sector ? Employee.for_checklist_tracking(@user).in_current_or_last_sector(@employee_sector).pluck(:id).to_set : nil
      matcher = NameMatcher.new(employees)
      accessible_ids = Task.accessible_to(@user).select(:id)
      TaskSource.candidates(@tasks.where(id: accessible_ids))
        .includes(:labels, :comments, :routine_comment, :checklist_occurrences, routine_value: :routine_indicator).find_each do |task|
        source = TaskSource.new(task)
        next unless source.suggested_date.year == @year
        next unless source.spot? == (@subject == "spot")
        matched = source.name_match(employees, matcher: matcher).employee
        next if selected_ids && matched && !selected_ids.include?(matched.id)
        if task.checklist_occurrences.any?
          result.preserved += 1
          next
        end
        attributes = source.automatic_attributes(employees, matcher: matcher)
        unless attributes
          result.pending += 1
          next
        end
        task.with_lock do
          next if task.checklist_occurrences.exists?
          occurrence = task.checklist_occurrences.create!(attributes.merge(recorded_by: @user,
            notes: source.spot? ? "Identificado automaticamente pela placa, data e tipo na ação ou no GEROT." : "Identificado automaticamente pelo nome e pelos dados da ação ou do GEROT."))
          TaskActivityService.log(task: task, user: @user, activity_type: :updated,
            new_value: "#{occurrence.subject_name} · #{I18n.l(occurrence.occurred_on)} · #{occurrence.kind_label}",
            metadata: { field: "checklist_occurrence", action: "registered", occurrence_id: occurrence.id,
                        identification_method: source.spot? ? "automatic_spot_plate" : "automatic_name" })
          result.created += 1
        end
      end
      result
    end
  end
end
