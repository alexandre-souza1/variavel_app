class CreateNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.references :notifiable, polymorphic: true
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body
      t.string :action_text
      t.string :action_url
      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications, [:user_id, :read_at, :created_at]
    add_index :notifications, [:kind, :created_at]
  end
end
