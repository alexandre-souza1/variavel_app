class CreateBuckets < ActiveRecord::Migration[7.1]
  def change
    create_table :buckets do |t|
      t.string :name
      t.integer :position
      t.references :action_plan, null: false, foreign_key: true

      t.timestamps
    end
  end
end
