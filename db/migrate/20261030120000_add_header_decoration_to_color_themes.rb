class AddHeaderDecorationToColorThemes < ActiveRecord::Migration[7.1]
  def up
    add_column :color_themes, :header_decoration, :jsonb, default: {}, null: false

    execute <<~SQL
      UPDATE color_themes
      SET header_decoration = '{"header_companion":"👻","header_detail":"✦"}'::jsonb
      WHERE key = 'halloween' AND decoration = '🎃'
    SQL
  end

  def down
    remove_column :color_themes, :header_decoration
  end
end
