class CreateAiSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_settings do |t|
      t.string :primary_model, null: false, default: "gemini-3.6-flash"
      t.integer :meeting_audio_max_minutes, null: false, default: 15
      t.timestamps
    end
  end
end
