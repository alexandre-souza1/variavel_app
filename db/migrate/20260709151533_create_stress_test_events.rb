class CreateStressTestEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :stress_test_events do |t|
      t.references :plate, foreign_key: true

      t.string :placa
      t.string :mapa
      t.string :fase
      t.date :operation_date
      t.time :operation_time
      t.string :motorista
      t.string :destino

      t.timestamps
    end
  end
end
