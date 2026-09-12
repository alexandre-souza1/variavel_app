class SetRetroOrangeAsInitialTheme < ActiveRecord::Migration[7.0]
  def up
    change_column_default :users, :color_theme, from: "sage_teal", to: "retro_orange"
    User.reset_column_information
    User.where(color_theme: "sage_teal").update_all(color_theme: "retro_orange")
  end

  def down
    change_column_default :users, :color_theme, from: "retro_orange", to: "sage_teal"
  end
end
