class CreateRoutineComments < ActiveRecord::Migration[7.1]
  def change
    create_table :routine_comments do |t|
      t.references :routine_value,
                   null: false,
                   foreign_key: true

      t.references :user,
                   null: false,
                   foreign_key: true

      t.text :body, null: false

      t.timestamps
    end
  end
end
