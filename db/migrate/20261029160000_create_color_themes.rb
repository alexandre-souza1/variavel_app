class CreateColorThemes < ActiveRecord::Migration[7.1]
  def up
    create_table :color_themes do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :description
      t.string :base_color, null: false
      t.string :primary_color, null: false
      t.string :accent_color, null: false
      t.string :highlight_color, null: false
      t.string :decoration
      t.boolean :promotion_enabled, null: false, default: false
      t.string :promotion_text
      t.date :promotion_starts_on
      t.date :promotion_ends_on
      t.timestamps
    end
    add_index :color_themes, :key, unique: true

    # O tema já existe nas preferências dos usuários; preservamos sua chave.
    theme = Class.new(ActiveRecord::Base) { self.table_name = "color_themes" }
    theme.create!(key: "halloween", name: "Halloween",
      description: "Roxos, pêssego e dourado com abóboras e pequenos sustos.",
      base_color: "#522D60", primary_color: "#80426E", accent_color: "#F2A67B", highlight_color: "#FFD38B",
      decoration: "🎃", promotion_enabled: true, promotion_text: "Experimente o Halloween",
      promotion_starts_on: Date.new(2026, 10, 29), promotion_ends_on: Date.new(2026, 11, 3))
  end

  def down
    execute <<~SQL
      UPDATE users SET color_theme = 'blue_teal'
      WHERE color_theme IN (SELECT key FROM color_themes WHERE key <> 'halloween')
    SQL
    drop_table :color_themes
  end
end
