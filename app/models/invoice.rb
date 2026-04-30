class Invoice < ApplicationRecord
  belongs_to :supplier
  belongs_to :purchaser, class_name: 'User', foreign_key: 'purchaser_id'
  has_many_attached :documents
  has_many :invoice_numbers, dependent: :destroy
  belongs_to :budget_category

  before_validation :ensure_code_for_abastecimento, on: :create

  accepts_nested_attributes_for :invoice_numbers, allow_destroy: true

  validates :purchaser_id, presence: true
  validates :date_issued, :due_date, :total, :supplier_id, :budget_category_id, presence: true
  validates :code, uniqueness: { allow_blank: true }

  # Validação customizada para o code
  validate :code_required_unless_abastecimento

  # Método para obter a lista de purchasers ativos
  def self.available_purchasers
    User.all.order(:name).pluck(:name, :id)
  end

  # Método para compatibilidade com views existentes
  def purchaser_name
    purchaser&.name
  end

  private

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
  
end
