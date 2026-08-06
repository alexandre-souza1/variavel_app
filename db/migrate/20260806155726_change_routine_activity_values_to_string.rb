class ChangeRoutineActivityValuesToString <
  ActiveRecord::Migration[7.1]

  def up
    change_column(
      :routine_activities,
      :previous_value,
      :string,
      using: "previous_value::text"
    )

    change_column(
      :routine_activities,
      :new_value,
      :string,
      using: "new_value::text"
    )
  end

  def down
    change_column(
      :routine_activities,
      :previous_value,
      :decimal,
      precision: 15,
      scale: 4,
      using: <<~SQL.squish
        CASE
          WHEN previous_value IS NULL OR previous_value = ''
            THEN NULL
          WHEN previous_value ~ '^-?[0-9]+([.][0-9]+)?$'
            THEN previous_value::numeric
          ELSE NULL
        END
      SQL
    )

    change_column(
      :routine_activities,
      :new_value,
      :decimal,
      precision: 15,
      scale: 4,
      using: <<~SQL.squish
        CASE
          WHEN new_value IS NULL OR new_value = ''
            THEN NULL
          WHEN new_value ~ '^-?[0-9]+([.][0-9]+)?$'
            THEN new_value::numeric
          ELSE NULL
        END
      SQL
    )
  end
end
