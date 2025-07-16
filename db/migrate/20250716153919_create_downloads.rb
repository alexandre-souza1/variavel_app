class CreateDownloads < ActiveRecord::Migration[7.1]
  def change
    create_table :downloads do |t|
      t.string :title
      t.string :description
      t.string :category
      t.string :file_type
      t.string :file_size
      t.string :url

      t.timestamps
    end
  end
end
