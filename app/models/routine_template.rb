class RoutineTemplate < ApplicationRecord
  belongs_to :action_plan, optional: true, inverse_of: :gerot_template
  has_many :routine_categories,
           -> { order(:position) },
           dependent: :destroy

  has_many :routines,
           dependent: :restrict_with_error

  enum :sector, User.sectors, prefix: true

  validates :name,
            presence: true,
            uniqueness: true

  validates :sector,
            presence: true
  validates :action_plan_id, uniqueness: true, allow_nil: true
  validate :matches_plan_sector

  after_create :create_bucket_categories, if: :action_plan_id?

  scope :active, -> { where(active: true) }
  scope :independent, -> { where(action_plan_id: nil) }
  scope :visible_to, lambda { |user|
    return all if user&.admin?

    independent.where(sector: user&.sector)
      .or(where(action_plan_id: ActionPlan.visible_to(user).select(:id)))
  }

  def manageable_by?(user)
    user.present? && (action_plan ? action_plan.manageable_by?(user) : user.admin? || sector == user.sector)
  end

  def default_selected_indicator_ids
    routine_categories.joins(:routine_indicators).pluck("routine_indicators.id")
  end

  private

  def matches_plan_sector
    return if action_plan.blank? || sector == action_plan.sector

    errors.add(:sector, "deve ser o mesmo do plano de ação")
  end

  def create_bucket_categories
    Routines::PlanTemplateSynchronizer.call(action_plan: action_plan, template: self)
  end
end
