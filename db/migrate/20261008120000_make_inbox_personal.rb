class MakeInboxPersonal < ActiveRecord::Migration[7.1]
  class LegacyBucket < ActiveRecord::Base
    self.table_name = "buckets"
  end

  class LegacyTask < ActiveRecord::Base
    self.table_name = "tasks"
  end

  def up
    change_column_null :buckets, :action_plan_id, true
    add_reference :buckets, :user, foreign_key: true
    LegacyBucket.reset_column_information

    LegacyBucket.where(inbox: true).where.not(action_plan_id: nil).find_each do |bucket|
      # GEROT categories and generated actions must keep their plan and history.
      linked = select_value(<<~SQL)
        SELECT EXISTS (
          SELECT 1 FROM routine_categories c
          JOIN routine_indicators i ON i.routine_category_id = c.id
          WHERE c.bucket_id = #{bucket.id}
          UNION ALL
          SELECT 1 FROM routine_category_buckets m
          JOIN routine_indicators i ON i.routine_category_id = m.routine_category_id
          WHERE m.bucket_id = #{bucket.id}
          UNION ALL
          SELECT 1 FROM tasks WHERE bucket_id = #{bucket.id} AND routine_value_id IS NOT NULL
        )
      SQL
      if linked
        bucket.update!(inbox: false)
        next
      end

      LegacyTask.where(bucket_id: bucket.id).find_each do |task|
        personal = LegacyBucket.find_or_create_by!(user_id: task.creator_id, inbox: true) do |new_bucket|
          new_bucket.name = "Entrada"
          new_bucket.position = -1
        end
        # Preserve former label information in the activity before detaching plan labels.
        labels = select_all("SELECT labels.id, labels.name, labels.color FROM labels JOIN task_labels ON task_labels.label_id = labels.id WHERE task_labels.task_id = #{task.id}").to_a
        metadata = { previous_action_plan_id: bucket.action_plan_id, previous_labels: labels }.to_json
        execute <<~SQL
          INSERT INTO task_activities (task_id, user_id, activity_type, old_value, new_value, metadata, created_at, updated_at)
          VALUES (#{task.id}, #{task.creator_id}, 'bucket_changed', 'Entrada do plano', 'Entrada pessoal', #{connection.quote(metadata)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
        task.update_columns(bucket_id: personal.id, position: LegacyTask.where(bucket_id: personal.id).count + 1)
        execute "DELETE FROM task_labels WHERE task_id = #{task.id}"
        execute "UPDATE notifications SET action_url = '/inbox?task_id=#{task.id}' WHERE notifiable_type = 'Task' AND notifiable_id = #{task.id} AND user_id = #{task.creator_id}"
        execute "DELETE FROM notifications WHERE notifiable_type = 'Task' AND notifiable_id = #{task.id} AND user_id <> #{task.creator_id}"
      end

      execute "DELETE FROM routine_category_buckets WHERE bucket_id = #{bucket.id} OR routine_category_id IN (SELECT id FROM routine_categories WHERE bucket_id = #{bucket.id})"
      execute "DELETE FROM routine_categories WHERE bucket_id = #{bucket.id}"
      bucket.destroy!
    end

    execute <<~SQL
      UPDATE tasks SET position = ordered.position
      FROM (
        SELECT tasks.id, ROW_NUMBER() OVER (PARTITION BY tasks.bucket_id ORDER BY tasks.created_at DESC, tasks.id DESC) AS position
        FROM tasks JOIN buckets ON buckets.id = tasks.bucket_id WHERE buckets.inbox = true
      ) ordered WHERE ordered.id = tasks.id
    SQL

    add_index :buckets, :user_id, unique: true, where: "inbox = true", name: "index_buckets_on_personal_inbox_owner"
    add_check_constraint :buckets,
      "(inbox = true AND user_id IS NOT NULL AND action_plan_id IS NULL) OR (inbox = false AND user_id IS NULL AND action_plan_id IS NOT NULL)",
      name: "buckets_owner_matches_inbox"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "As Entradas pessoais consolidam tarefas de vários planos."
  end
end
