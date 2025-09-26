class AddDetailsToSuppliers < ActiveRecord::Migration[7.1]
  def change
    add_column :suppliers, :fantasy_name, :string
    add_column :suppliers, :situation, :string
    add_column :suppliers, :email, :string
    add_column :suppliers, :phone, :string
    add_column :suppliers, :street, :string
    add_column :suppliers, :number, :string
    add_column :suppliers, :complement, :string
    add_column :suppliers, :neighborhood, :string
    add_column :suppliers, :city, :string
    add_column :suppliers, :state, :string
    add_column :suppliers, :zip_code, :string
  end
end
