class AddValidityToInvoiceGoals < ActiveRecord::Migration[7.1]
  def up
    add_column :invoice_goals, :ends_at, :date

    # Preserve historical monthly entries, including gaps. Only the latest
    # entry for each indicator continues automatically into following months.
    execute <<~SQL
      UPDATE invoice_goals AS goal
      SET ends_at = (goal.reference_month + INTERVAL '1 month - 1 day')::date
      WHERE EXISTS (
        SELECT 1 FROM invoice_goals AS newer
        WHERE newer.sector = goal.sector
          AND newer.name = goal.name
          AND newer.reference_month > goal.reference_month
      )
    SQL
  end

  def down
    remove_column :invoice_goals, :ends_at
  end
end
