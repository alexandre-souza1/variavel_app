class AddStressTestImportToStressTestEvents < ActiveRecord::Migration[7.1]
  def change
    add_reference :stress_test_events,
                  :stress_test_import,
                  foreign_key: true
  end
end
