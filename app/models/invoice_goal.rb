class InvoiceGoal < ApplicationRecord
  has_many :invoice_goal_categories, dependent: :destroy
  has_many :budget_categories, through: :invoice_goal_categories

  SECTORS = BudgetCategory.sectors.freeze

  enum :sector, SECTORS

  accepts_nested_attributes_for :invoice_goal_categories, allow_destroy: true

  before_validation :normalize_reference_month

  validates :name, :sector, :reference_month, presence: true
  validates :target_amount, numericality: { greater_than: 0 }
  validates :name, uniqueness: { scope: [:sector, :reference_month] }
  validate :must_have_categories
  validate :categories_must_belong_to_goal_sector

  def reference_month=(value)
    value = Date.strptime(value, "%Y-%m").beginning_of_month if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}\z/)
    super(value)
  end

  private

  def normalize_reference_month
    value = reference_month.to_s
    self.reference_month = Date.strptime(value, "%Y-%m").beginning_of_month if value.match?(/\A\d{4}-\d{2}\z/)
    self.reference_month = reference_month.beginning_of_month if reference_month.respond_to?(:beginning_of_month)
  end

  def must_have_categories
    errors.add(:budget_categories, "selecione pelo menos uma categoria") if budget_categories.empty?
  end

  def categories_must_belong_to_goal_sector
    return if sector.blank? || budget_categories.empty?

    expected_sector = BudgetCategory.sectors[sector]
    invalid_categories = budget_categories.reject { |category| category.sector == sector || category.sector == expected_sector }
    return if invalid_categories.empty?

    errors.add(:budget_categories, "devem pertencer ao setor #{expected_sector}")
  end
end
