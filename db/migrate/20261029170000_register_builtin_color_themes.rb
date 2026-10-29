class RegisterBuiltinColorThemes < ActiveRecord::Migration[7.1]
  THEMES = [
    ["blue_teal", "Blue-Teal", "Azul equilibrado com detalhes em azul-petróleo.", %w[#3368A0 #66A3BF #C8DFDB #F2EFE7]],
    ["sage_teal", "Sage-Teal", "Verde-azulado suave e corporativo.", %w[#2D9596 #265073 #9AD0C2 #ECF4D6]],
    ["retro_orange", "Retro-orange", "Creme, verde e laranja com personalidade.", %w[#527853 #F9E8D9 #F7B787 #EE7214]],
    ["black_mint", "BLACK-MINT", "Base escura com verdes menta marcantes.", %w[#092328 #12544F #2A835F #8BBB92]],
    ["white_tea_sage", "WHITE-TEA&SAGE", "Tons claros e naturais de chá branco e sálvia.", %w[#8B9A6E #F7F2EB #EAE2D6 #EEEEEE]],
    ["earthy_forest_hues", "EARTHY-FOREST-HUES", "Tons terrosos e verdes inspirados na floresta.", %w[#DAD7CD #A3B18A #588157 #3A5A40 #344E41]]
  ].freeze

  def up
    add_column :color_themes, :preserve_original_palette, :boolean, null: false, default: false
    add_column :color_themes, :extra_color, :string

    theme_class = Class.new(ActiveRecord::Base) { self.table_name = "color_themes" }
    THEMES.each do |key, name, description, colors|
      theme_class.find_or_create_by!(key: key) do |theme|
        theme.assign_attributes(name: name, description: description,
          base_color: colors[0], primary_color: colors[1], accent_color: colors[2], highlight_color: colors[3],
          extra_color: colors[4], preserve_original_palette: true, promotion_enabled: false)
      end
    end
  end

  def down
    theme_class = Class.new(ActiveRecord::Base) { self.table_name = "color_themes" }
    theme_class.where(key: THEMES.map(&:first)).delete_all
    remove_column :color_themes, :extra_color
    remove_column :color_themes, :preserve_original_palette
  end
end
