class ActionPlan < ApplicationRecord
  enum :sector, User.sectors, prefix: true

  scope :visible_to, ->(user) do
    return all if user.admin?

    left_joins(buckets: { tasks: :task_assignments })
      .where(
        'action_plans."public" = :public OR
         action_plans.user_id = :user_id OR
         action_plans.sector = :sector OR
         tasks.creator_id = :user_id OR
         task_assignments.user_id = :user_id',
        public: true,
        user_id: user.id,
        sector: User.sectors[user.sector]
      )
      .distinct
  end

  belongs_to :user
  has_many :buckets, dependent: :destroy
  has_many :labels, dependent: :destroy
  has_many :meeting_minutes, dependent: :destroy
  has_many :hidden_action_plans, dependent: :destroy

  validates :name, presence: true

  before_validation :inherit_user_sector, on: :create

  after_create :create_default_buckets

  def create_default_buckets
    buckets.create!(name: "Entrada", position: -1, inbox: true)

    ["A Fazer", "Em Andamento", "Concluído"].each_with_index do |name, index|
      buckets.create!(
        name: name,
        position: index
      )
    end
  end

  def inbox_bucket
    buckets.find_by(inbox: true)
  end

  private

  def inherit_user_sector
    self.sector ||= user&.sector
  end

end
