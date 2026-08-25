class AzRvImport < ApplicationRecord
  belongs_to :user, optional: true
  has_many :az_rv_points, dependent: :destroy
  has_many :az_rv_tasks, dependent: :destroy
  has_many :az_rv_on_demand_activities, dependent: :destroy
  has_many :wms_tasks, dependent: :destroy

  validates :source_type, :original_filename, :file_digest, :status, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def source_label
    {
      "points" => "Pontos",
      "tasks" => "Tarefas",
      "ondemand" => "On Demand"
    }.fetch(source_type, source_type.humanize)
  end
end
