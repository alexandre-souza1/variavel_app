class AddStressTestImportToStressTestEvents < ActiveRecord::Migration[7.1]
  def change
    add_reference :stress_test_events,
                  :stress_test_import,
                  null: false,
                  foreign_key: true

    change_column_null :stress_test_events, :plate_id, true
  end
end
