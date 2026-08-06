class ChangeRoutineIndicatorTargetsGoalToString <
  ActiveRecord::Migration[7.1]

  def up
    change_column(
      :routine_indicator_targets,
      :goal,
      :string,
      null: false,
      using: "goal::text"
    )
  end

  def down
    change_column(
      :routine_indicator_targets,
      :goal,
      :decimal,
      precision: 15,
      scale: 4,
      null: false,
      using: <<~SQL.squish
        CASE
          WHEN goal ~ '^-?[0-9]+([.][0-9]+)?$'
            THEN goal::numeric
          ELSE 0
        END
      SQL
    )
  end
end
