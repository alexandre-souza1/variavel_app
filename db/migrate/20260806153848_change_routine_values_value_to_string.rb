class ChangeRoutineValuesValueToString < ActiveRecord::Migration[7.1]
  def up
    change_column(
      :routine_values,
      :value,
      :string,
      using: "value::text"
    )
  end

  def down
    change_column(
      :routine_values,
      :value,
      :decimal,
      precision: 15,
      scale: 4,
      using: <<~SQL.squish
        CASE
          WHEN value IS NULL OR value = '' THEN NULL
          WHEN value ~ '^-?[0-9]+([.][0-9]+)?$' THEN value::numeric
          ELSE NULL
        END
      SQL
    )
  end
end
