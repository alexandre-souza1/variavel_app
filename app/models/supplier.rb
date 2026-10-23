class Supplier < ApplicationRecord
  has_many :fleet_availability_items, dependent: :restrict_with_error
  has_many :fleet_availability_changes, dependent: :restrict_with_error
  has_many :invoices, dependent: :destroy
  TYPES = {
    "workshop" => "Oficina",
    "tire_shop" => "Borracharia",
    "store" => "Loja",
    "fuel_station" => "Posto de combustível",
    "contractor" => "Contratadas",
    "other" => "Outros"
  }.freeze
  MAINTENANCE_TYPES = %w[workshop tire_shop].freeze

  scope :maintenance_providers, -> { where(supplier_type: MAINTENANCE_TYPES) }
  validates :supplier_type, inclusion: { in: TYPES.keys }
  validates :name, :cnpj, presence: true
  validates :cnpj, uniqueness: true

  # Validação opcional para formatar o CNPJ
  before_save :format_cnpj

  def supplier_type_label
    TYPES[supplier_type]
  end

  def provides_maintenance?
    MAINTENANCE_TYPES.include?(supplier_type)
  end

  def display_name
    fantasy_name.to_s.strip.presence || name
  end

  private

  def format_cnpj
    # Remove caracteres não numéricos e formata
    self.cnpj = cnpj.gsub(/\D/, '') if cnpj.present?
  end
end
