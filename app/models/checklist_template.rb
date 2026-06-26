class ChecklistTemplate < ApplicationRecord

  has_many :checklist_items, dependent: :destroy
  has_many :checklists, dependent: :destroy

  validates :name, presence: true


  attribute :plate_required, :boolean, default: false
  attribute :kilometer_required, :boolean, default: false
  attribute :gas_state_required, :boolean, default: false
  attribute :vehicle_model_required, :boolean, default: false
  attribute :responsavel_required, :boolean, default: false
  attribute :origin_required, :boolean, default: false
  attribute :photos_required, :boolean, default: false
  attribute :five_s_az, :boolean, default: false


  def photo_only?
    photos_required? && !checklist_items.exists?
  end


  def five_s_az?
    five_s_az
  end

end
