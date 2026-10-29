class InvoiceGoal < ApplicationRecord
  has_many :invoice_goal_categories, dependent: :destroy
  has_many :budget_categories, through: :invoice_goal_categories

  SECTORS = BudgetCategory.sectors.freeze

  enum :sector, SECTORS

  accepts_nested_attributes_for :invoice_goal_categories, allow_destroy: true

  before_validation :normalize_months

  validates :name, :sector, :reference_month, presence: true
  validates :target_amount, numericality: { greater_than: 0 }
  validates :name, uniqueness: { scope: [:sector, :reference_month] }
  validate :must_have_categories
  validate :categories_must_belong_to_goal_sector
  validate :ends_at_not_before_reference_month

  # As in GEROT, the most recent applicable validity takes precedence.
  # Keep this as a relation so all consumers retain their sector filters.
  def self.effective_on(date)
    month = date.to_date.beginning_of_month
    applicable = where("reference_month <= ?", month)
      .where("ends_at IS NULL OR ends_at >= ?", month)
    where(id: applicable
      .select("DISTINCT ON (invoice_goals.sector, invoice_goals.name) invoice_goals.id")
      .reorder(:sector, :name, reference_month: :desc))
  end

  def reference_month=(value)
    value = Date.strptime(value, "%Y-%m").beginning_of_month if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}\z/)
    super(value)
  rescue Date::Error
    super(nil)
  end

  # A change belongs to the same indicator. Choosing an existing start month
  # corrects that entry; another month creates a new entry without copying history.
  def change_from(attributes)
    month = self.class.new(reference_month: attributes[:reference_month]).reference_month&.beginning_of_month
    result = nil
    self.class.transaction do
      versions = self.class.where(name: name, sector: sector)
      versions.order(:id).first.lock!
      result = versions.find_or_initialize_by(reference_month: month)
      result.target_amount = attributes[:target_amount]
      result.ends_at = nil
      result.budget_categories = if attributes.key?(:budget_category_ids)
        BudgetCategory.where(id: attributes[:budget_category_ids])
      else
        budget_categories
      end
      raise ActiveRecord::Rollback unless result.save
    end
    result
  end

  def ends_at=(value)
    value = Date.strptime(value, "%Y-%m").end_of_month if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}\z/)
    super(value)
  end

  private

  def normalize_months
    value = reference_month.to_s
    self.reference_month = Date.strptime(value, "%Y-%m").beginning_of_month if value.match?(/\A\d{4}-\d{2}\z/)
    self.reference_month = reference_month.beginning_of_month if reference_month.respond_to?(:beginning_of_month)
    self.ends_at = ends_at.end_of_month if ends_at.present?
  end

  def ends_at_not_before_reference_month
    return if reference_month.blank? || ends_at.blank? || ends_at >= reference_month

    errors.add(:ends_at, "não pode ser anterior ao mês inicial")
  end

  def must_have_categories
    errors.add(:budget_categories, "selecione pelo menos uma categoria") if budget_categories.empty?
  end

  def categories_must_belong_to_goal_sector
    return if sector.blank? || budget_categories.empty?

    expected_sector = sector.to_s
    invalid_categories = budget_categories.reject { |category| category.sector == expected_sector }
    return if invalid_categories.empty?

    errors.add(:budget_categories, "devem pertencer ao setor #{BudgetCategory.sectors[expected_sector]}")
  end
end
