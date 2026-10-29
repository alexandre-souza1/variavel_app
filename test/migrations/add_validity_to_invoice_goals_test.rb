require "test_helper"
require Rails.root.join("db/migrate/20261028120000_add_validity_to_invoice_goals")

class AddValidityToInvoiceGoalsTest < ActiveSupport::TestCase
  test "preserves historical months and gaps while opening only the latest validity per indicator and sector" do
    connection = ActiveRecord::Base.connection
    # PostgreSQL resolves this temporary table before the application's table.
    connection.execute <<~SQL
      CREATE TEMPORARY TABLE invoice_goals (
        id integer PRIMARY KEY, name text, sector text, reference_month date
      ) ON COMMIT DROP;
      INSERT INTO invoice_goals (id, name, sector, reference_month) VALUES
        (1, 'Manutenção', 'FROTA', '2026-07-01'),
        (2, 'Manutenção', 'FROTA', '2026-09-01'),
        (3, 'Manutenção', 'FROTA', '2026-10-01'),
        (4, 'Manutenção', 'ROTA', '2026-08-01'),
        (5, 'Combustível', 'FROTA', '2026-09-01');
    SQL
    migration = AddValidityToInvoiceGoals.new
    migration.suppress_messages { migration.up }

    rows = connection.select_all("SELECT id, reference_month, ends_at FROM invoice_goals ORDER BY id").to_a
    assert_equal 5, rows.size
    assert_equal ["2026-07-31", "2026-09-30", nil, nil, nil], rows.map { |row| row["ends_at"]&.to_s }
    assert_equal "2026-07-01", rows.first.fetch("reference_month").to_s

    migration.suppress_messages { migration.down }
    assert_equal 5, connection.select_value("SELECT COUNT(*) FROM invoice_goals")
    refute connection.column_exists?(:invoice_goals, :ends_at)
  ensure
    connection&.execute("DROP TABLE IF EXISTS pg_temp.invoice_goals")
    connection&.clear_cache!
  end
end
