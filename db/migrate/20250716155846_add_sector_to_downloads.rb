class AddSectorToDownloads < ActiveRecord::Migration[7.1]
  def change
    add_column :downloads, :sector, :string
  end
end
