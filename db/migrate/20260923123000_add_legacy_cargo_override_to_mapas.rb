class AddLegacyCargoOverrideToMapas < ActiveRecord::Migration[7.1]
  def change
    add_column :mapas, :cargo_override, :string
    add_column :mapas, :cargo_override_reason, :text
    add_column :mapas, :cargo_override_at, :datetime
    add_reference :mapas, :cargo_override_user, foreign_key: { to_table: :users }
    add_check_constraint :mapas,
      "cargo_override IS NULL OR cargo_override IN ('motorista', 'van', 'ajudante')",
      name: 'mapa_valid_cargo_override'

    create_table :mapa_cargo_overrides do |t|
      t.references :mapa, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :previous_cargo
      t.string :cargo
      t.text :reason, null: false
      t.timestamps
    end
    add_check_constraint :mapa_cargo_overrides,
      "previous_cargo IS NULL OR previous_cargo IN ('motorista', 'van', 'ajudante')",
      name: 'mapa_override_valid_previous_cargo'
    add_check_constraint :mapa_cargo_overrides,
      "cargo IS NULL OR cargo IN ('motorista', 'van', 'ajudante')",
      name: 'mapa_override_valid_cargo'
  end
end
