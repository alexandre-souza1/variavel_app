class Bucket < ApplicationRecord
  belongs_to :action_plan, optional: true
  belongs_to :user, optional: true
  validates :name, presence: true
  validates :user_id, uniqueness: true, if: :inbox?
  validate :validate_ownership
  has_one :routine_category
  has_many :routine_category_buckets, dependent: :restrict_with_error
  has_many :tasks, dependent: :destroy

  scope :work, -> { where(inbox: false) }

  default_scope { order(:position) }

  after_save :sync_gerot_category
  before_destroy :remove_unused_gerot_category, prepend: true

  def open_count
    tasks.where(completed: false).count
  end

  def done_count
    tasks.where(completed: true).count
  end

  private

  def validate_ownership
    valid = inbox? ? user.present? && action_plan.nil? : action_plan.present? && user.nil?
    errors.add(:base, "A Entrada pertence a um usuário; os demais buckets pertencem a um plano.") unless valid
  end

  def sync_gerot_category
    return if inbox?
    return unless saved_change_to_name? || saved_change_to_position? || previously_new_record?

    Routines::PlanTemplateSynchronizer.call(action_plan: action_plan)
  end

  def remove_unused_gerot_category
    category = routine_category
    return unless category && !category.destroyed?
    return if category.destroy

    errors.add(:base, "Este bucket tem indicadores com preenchimentos de GEROT e não pode ser excluído.")
    throw :abort
  end
end
