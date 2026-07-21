class AdjustFleetAvailabilityTables < ActiveRecord::Migration[7.1]
  def change
    # Renomeia a coluna para representar melhor a regra de negócio
    rename_column :fleet_availabilities,
                  :planned_quantity,
                  :agreed_quantity

    # Constraints
    change_column_null :fleet_availabilities,
                       :agreed_quantity,
                       false

    change_column_null :fleet_availability_items,
                       :status,
                       false

    change_column_null :fleet_availability_items,
                       :position,
                       false

    # Índice composto para impedir duas disponibilidades no mesmo dia para o mesmo usuário
    remove_index :fleet_availabilities, :user_id

    add_index :fleet_availabilities,
              [:user_id, :date],
              unique: true,
              name: "idx_fleet_availability_user_date"

    # Uma placa só pode aparecer uma vez por disponibilidade
    add_index :fleet_availability_items,
              [:fleet_availability_id, :plate_id],
              unique: true,
              name: "idx_fleet_availability_item"
  end
end
