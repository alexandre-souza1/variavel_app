class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  attr_accessor :remove_photo

  has_many :checklists
  has_many :invoices, foreign_key: 'purchaser_id', dependent: :nullify
  has_many :action_plans, dependent: :destroy
  has_many :task_assignments
  has_many :tasks, through: :task_assignments
  has_many :stress_test_imports, dependent: :destroy
  has_many :fleet_availabilities, dependent: :destroy

  scope :active, -> { where.not(confirmed_at: nil) }

  has_one_attached :photo do |attachable|
    attachable.variant :thumb, resize_to_limit: [150, 150]
  end

  enum :sector, {
    fleet: 0,
    du: 1,
    warehouse: 2,
    hr: 3,
    safety: 4,
    finance: 5,
    planning: 6
  }, prefix: true

  USER_SECTORS = {
    "Frota" => :fleet,
    "DU" => :du,
    "Armazém" => :warehouse,
    "RH" => :hr,
    "Segurança" => :safety,
    "Financeiro" => :finance,
    "Planejamento" => :planning
  }.freeze

    enum role: { user: 0, supervisor: 1, admin: 2, mechanical: 3}

  # Defina um valor padrão, se quiser
  after_initialize do
    if self.new_record?
      self.role ||= :user
    end
  end
end
