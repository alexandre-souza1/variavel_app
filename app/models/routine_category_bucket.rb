class RoutineCategoryBucket < ApplicationRecord
  belongs_to :action_plan
  belongs_to :routine_category
  belongs_to :bucket

  validates :routine_category_id, uniqueness: { scope: :action_plan_id }
  validate :bucket_belongs_to_plan

  private

  def bucket_belongs_to_plan
    return if bucket&.action_plan_id == action_plan_id

    errors.add(:bucket, "deve pertencer ao plano de ação")
  end
end
