class CreatePushDevices < ActiveRecord::Migration[7.1]
  def change
    create_table :push_devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false, limit: 2048
      t.string :session_binding, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :push_devices, :token, unique: true
    add_index :push_devices, [:user_id, :session_binding]
  end
end
