class AddColorThemeToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :color_theme, :string, null: false, default: "blue_teal"
  end
end
