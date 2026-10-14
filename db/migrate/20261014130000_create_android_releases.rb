class CreateAndroidReleases < ActiveRecord::Migration[7.1]
  def change
    create_table :android_releases do |t|
      t.string :channel, null: false, default: "release"
      t.integer :version_code, null: false
      t.string :version_name, null: false
      t.text :notes
      t.string :sha256, null: false
      t.bigint :byte_size, null: false
      t.boolean :published, null: false, default: true
      t.timestamps
    end
    add_index :android_releases, %i[channel version_code], unique: true
    add_check_constraint :android_releases, "version_code > 0 AND byte_size > 0", name: "android_releases_positive_values"
  end
end
