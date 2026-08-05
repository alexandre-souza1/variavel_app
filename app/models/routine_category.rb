class RoutineCategory < ApplicationRecord
  belongs_to :routine_template

  has_many :routine_indicators,
           -> { order(:position) },
           dependent: :destroy

  validates :name,
            presence: true

  validates :position,
            presence: true

  before_create :shift_positions_on_create
  before_update :reorder_positions, if: :will_save_change_to_position?


  private

  def reorder_positions
    old_position = position_in_database
    new_position = position

    return if old_position == new_position

    if new_position < old_position
      self.class
          .where(routine_template_id: routine_template_id)
          .where(position: new_position...old_position)
          .where.not(id: id)
          .update_all("position = position + 1")
    else
      self.class
          .where(routine_template_id: routine_template_id)
          .where(position: (old_position + 1)..new_position)
          .where.not(id: id)
          .update_all("position = position - 1")
    end
  end

  def shift_positions_on_create
    self.class
        .where(routine_template_id: routine_template_id)
        .where("position >= ?", position)
        .update_all("position = position + 1")
  end
end
