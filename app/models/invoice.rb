class Invoice < ApplicationRecord
  scope :visible_to, ->(user) do
    return none if user.nil? || user.mechanical?
    return all if user.admin? || user.sector_finance?

    joins(:budget_category).where(budget_categories: { sector: user.budget_sectors })
  end
  belongs_to :supplier
  belongs_to :purchaser, class_name: 'User', foreign_key: 'purchaser_id'
  belongs_to :created_by, class_name: 'User', optional: true
  has_many_attached :documents
  has_many :invoice_numbers, dependent: :destroy
  belongs_to :budget_category

  before_validation :ensure_code_for_abastecimento, on: :create
  before_validation :calculate_total_from_invoice_numbers

  accepts_nested_attributes_for :invoice_numbers, allow_destroy: true

  validates :purchaser_id, presence: true
  validates :date_issued, :due_date, :total, :supplier_id, :budget_category_id, presence: true
  validates :code, uniqueness: { allow_blank: true }

  # Validação customizada para o code
  validate :code_required_unless_abastecimento
  validate :date_issued_not_in_future
  validate :purchaser_matches_budget_category_sector, if: :sector_relationship_changed?

  # Método para obter a lista de purchasers ativos
  def self.available_purchasers
    User.all.order(:name).pluck(:name, :id)
  end

  # Método para compatibilidade com views existentes
  def purchaser_name
    purchaser&.name
  end

  DOCUMENT_TYPES = {
    nf: "Nota Fiscal",
    boleto: "Boleto",
    outro: "Outro"
  }.freeze

  private

  def date_issued_not_in_future
    return if date_issued.blank? || date_issued <= Date.current

    errors.add(:date_issued, "não pode ser maior que a data atual")
  end

  def sector_relationship_changed?
    new_record? || will_save_change_to_purchaser_id? || will_save_change_to_budget_category_id?
  end

  def purchaser_matches_budget_category_sector
    return if purchaser.blank? || budget_category.blank?
    return if budget_category.user_sector.blank? || purchaser.sector.blank?
    return if purchaser.sector.to_sym == budget_category.user_sector

    errors.add(:purchaser, "deve pertencer ao setor #{BudgetCategory.sectors[budget_category.sector]}")
  end

  def code_required_unless_abastecimento
    # Se NÃO for abastecimento E code estiver em branco, adiciona erro
    if budget_category&.name&.downcase != 'abastecimento' && code.blank?
      errors.add(:code, "é obrigatório para esta categoria")
    end
  end

  def ensure_code_for_abastecimento
    # Se for abastecimento e não tiver código, gera um automático
    if budget_category&.name&.downcase == 'abastecimento' && code.blank?
      self.code = "ABAST-#{Date.today.strftime('%Y%m%d')}-#{SecureRandom.alphanumeric(6).upcase}"
    end
  end

  def calculate_total_from_invoice_numbers
    self.total = invoice_numbers.reject(&:marked_for_destruction?).sum do |invoice_number|
      amount = invoice_number.amount
      if amount.is_a?(String)
        amount.gsub('.', '').tr(',', '.').to_d
      else
        amount.to_d
      end
    end
  end

end
