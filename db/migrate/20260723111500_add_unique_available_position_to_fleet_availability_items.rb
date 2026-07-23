class AddUniqueAvailablePositionToFleetAvailabilityItems < ActiveRecord::Migration[7.1]
  def up
    normalize_available_positions

    add_index :fleet_availability_items,
              %i[fleet_availability_id position],
              unique: true,
              where: "status = 0",
              name: "index_fleet_availability_items_on_unique_available_position"
  end

  def down
    remove_index :fleet_availability_items,
                 name: "index_fleet_availability_items_on_unique_available_position"
  end

  private

  def normalize_available_positions
    availability_ids = select_values("SELECT id FROM fleet_availabilities")

    availability_ids.each do |availability_id|
      items = select_all(<<~SQL.squish)
        SELECT id, position
        FROM fleet_availability_items
        WHERE fleet_availability_id = #{connection.quote(availability_id)}
          AND status = 0
        ORDER BY position, id
      SQL

      used_positions = []
      next_position = 0

      items.each do |item|
        position = item["position"].to_i

        if position.negative? || used_positions.include?(position)
          next_position += 1 while used_positions.include?(next_position)
          position = next_position

          execute <<~SQL.squish
            UPDATE fleet_availability_items
            SET position = #{connection.quote(position)}
            WHERE id = #{connection.quote(item["id"])}
          SQL
        end

        used_positions << position
      end
    end
  end
end
