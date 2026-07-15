class CreateTaskActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :task_activities do |t|

      t.timestamps
    end
  end
end
