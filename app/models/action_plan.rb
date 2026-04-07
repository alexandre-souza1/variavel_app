class ActionPlan < ApplicationRecord
  belongs_to :user
  has_many :buckets, dependent: :destroy

  validates :name, presence: true

  after_create :create_default_buckets

  def create_default_buckets
    ["A Fazer", "Em Andamento", "Concluído"].each_with_index do |name, index|
      buckets.create!(
        name: name,
        position: index
      )
    end
  end

end
