module ActionPlans
  class Dashboard
    SOURCES = %w[all gerot manual].freeze
    STATUSES = { open: "Abertas no prazo", overdue: "Atrasadas", completed: "Concluídas" }.freeze

    attr_reader :source, :tasks, :counts, :buckets, :members, :generated_count, :unassigned_count

    def initialize(action_plan:, user:, source: nil, now: Time.current)
      @now = now
      @source = SOURCES.include?(source) ? source : "all"
      visible_ids = Task.joins(:bucket).where(buckets: { action_plan_id: action_plan.id }).visible_for(user).select(:id)
      @scope = Task.where(id: visible_ids)
      @scope = @scope.where.not(routine_value_id: nil) if @source == "gerot"
      @scope = @scope.where(routine_value_id: nil) if @source == "manual"
      @tasks = @scope.includes(:users, :bucket).to_a
      @counts = tally(@tasks)
      @generated_count = @tasks.count { |task| task.routine_value_id.present? }
      @unassigned_count = @tasks.count { |task| task.users.empty? }
      grouped = @tasks.group_by(&:bucket_id)
      @buckets = action_plan.buckets.order(:position, :id).map do |bucket|
        { id: bucket.id, name: bucket.name, counts: tally(grouped.fetch(bucket.id, [])) }
      end
      assignments = @tasks.flat_map { |task| task.users.map { |member| [member, task] } }
      @members = assignments.group_by { |member, _task| member.id }.map do |id, rows|
        { id: id, name: rows.first.first.name.presence || rows.first.first.email, counts: tally(rows.map(&:last).uniq(&:id)) }
      end.sort_by { |row| [-row[:counts].values.sum, row[:name].downcase] }
      @members << { id: "unassigned", name: "Sem responsável", counts: tally(@tasks.select { |task| task.users.empty? }) }
    end

    def total
      counts.values.sum
    end

    def completion_percentage
      total.zero? ? 0 : (counts[:completed] * 100.0 / total).round
    end

    def filtered_tasks(status: nil, bucket_id: nil, member_id: nil)
      scope = @scope
      case status
      when "open" then scope = scope.where(completed: [false, nil]).where("due_at IS NULL OR due_at >= ?", @now)
      when "overdue" then scope = scope.where(completed: [false, nil]).where("due_at < ?", @now)
      when "completed" then scope = scope.where(completed: true)
      end
      scope = scope.where(bucket_id: bucket_id) if bucket_id.present?
      if member_id == "unassigned"
        scope = scope.where.not(id: TaskAssignment.select(:task_id))
      elsif member_id.present?
        scope = scope.where(id: TaskAssignment.where(user_id: member_id).select(:task_id))
      end
      scope.includes(:bucket, :users, routine_value: :routine)
        .order(Arel.sql("CASE WHEN tasks.completed = TRUE THEN 1 ELSE 0 END, tasks.due_at ASC NULLS LAST, tasks.id DESC"))
    end

    def status(task)
      return :completed if task.completed?
      task.due_at.present? && task.due_at < @now ? :overdue : :open
    end

    private

    def tally(tasks)
      tasks.each_with_object(STATUSES.keys.index_with { 0 }) { |task, result| result[status(task)] += 1 }
    end
  end
end
