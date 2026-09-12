class SetBlueTealAsDefaultTheme < ActiveRecord::Migration[7.0]
  def up
    change_column_default :users, :color_theme, from: "retro_orange", to: "blue_teal"
    User.reset_column_information
    User.update_all(color_theme: "blue_teal")
  end

  def down
    change_column_default :users, :color_theme, from: "blue_teal", to: "retro_orange"
  end
end
