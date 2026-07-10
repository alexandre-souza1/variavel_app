class CreateStressTestImports < ActiveRecord::Migration[7.1]
  def change
    create_table :stress_test_imports do |t|
      t.references :user, null: false, foreign_key: true

      t.datetime :imported_at

      t.timestamps
    end
  end
end
