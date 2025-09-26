class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  attr_accessor :remove_photo

  has_many :checklists
  has_many :invoices, foreign_key: 'purchaser_id', dependent: :nullify

  scope :active, -> { where.not(confirmed_at: nil) }

  has_one_attached :photo do |attachable|
    attachable.variant :thumb, resize_to_limit: [150, 150]
  end

    enum role: { user: 0, supervisor: 1, admin: 2 }

  # Defina um valor padrão, se quiser
  after_initialize do
    if self.new_record?
      self.role ||= :user
    end
  end
end
