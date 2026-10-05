class RoutineCategory < ApplicationRecord
  belongs_to :routine_template
  belongs_to :bucket, optional: true
  has_many :routine_category_buckets, dependent: :destroy

  has_many :routine_indicators,
           -> { order(:position) },
           dependent: :destroy

  validates :name,
            presence: true
  validates :name, uniqueness: { scope: :routine_template_id }, unless: :bucket_id?

  validates :position,
            presence: true
  validates :bucket_id, uniqueness: true, allow_nil: true
  validate :bucket_matches_template
  before_validation :inherit_bucket_fields, if: :bucket_id?

  before_create :shift_positions_on_create
  before_update :reorder_positions, if: :will_save_change_to_position?


  private

  def inherit_bucket_fields
    self.name = bucket.name
    self.position = bucket.position
  end

  def bucket_matches_template
    plan_id = routine_template&.action_plan_id
    return if plan_id.nil? && bucket.nil?
    return if plan_id.present? && bucket&.action_plan_id == plan_id

    errors.add(:bucket, "deve pertencer ao plano do modelo de GEROT")
  end

  def reorder_positions
    return if bucket_id?
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
    return if bucket_id?
    self.class
        .where(routine_template_id: routine_template_id)
        .where("position >= ?", position)
        .update_all("position = position + 1")
  end
end
