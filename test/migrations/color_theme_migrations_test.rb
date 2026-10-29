require "test_helper"
require Rails.root.join("db/migrate/20261029160000_create_color_themes")
require Rails.root.join("db/migrate/20261029170000_register_builtin_color_themes")

# Um esquema isolado permite repetir a instalação inicial sem tocar nos cadastros.
class ColorThemeMigrationsTest < Minitest::Test
  def test_both_theme_migrations_run_with_the_first_table_schema_cached
    connection = ActiveRecord::Base.connection
    original_path = connection.schema_search_path
    schema = "color_theme_migrations_#{SecureRandom.hex(6)}"
    verbose = ActiveRecord::Migration.verbose
    connection.create_schema(schema)
    begin
      connection.schema_search_path = schema
      connection.schema_cache.clear!
      ActiveRecord::Migration.verbose = false

      CreateColorThemes.new.migrate(:up)
      assert_includes connection.schema_cache.columns_hash("color_themes").keys, "base_color"
      refute_includes connection.schema_cache.columns_hash("color_themes").keys, "extra_color"

      RegisterBuiltinColorThemes.new.migrate(:up)
      themes = Class.new(ActiveRecord::Base) { self.table_name = "color_themes" }
      themes.reset_column_information
      assert_equal 7, themes.count
      assert_equal 6, themes.where(preserve_original_palette: true).count
      assert_equal "#344E41", themes.find_by!(key: "earthy_forest_hues").extra_color
      assert themes.find_by!(key: "halloween").promotion_enabled?
    ensure
      connection.schema_search_path = original_path
      connection.schema_cache.clear!
      connection.drop_schema(schema, if_exists: true)
      ActiveRecord::Migration.verbose = verbose
    end
  end
end
