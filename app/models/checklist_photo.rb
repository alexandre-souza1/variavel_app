class ChecklistPhoto < ApplicationRecord
  belongs_to :checklist

  has_one_attached :photo,
                 service: :cloudinary

  enum :kind, {
    standard: "standard",
    defect: "defect",
    horimetro: "horimetro",
    interna: "interna",
    oleo: "oleo",
    agua: "agua",
    limpeza: "limpeza"
  }

  validates :photo, presence: true
  validates :kind, presence: true

  validates :description,
            presence: true,
            if: :defect?

  def defect?
    kind == "defect"
  end
end
