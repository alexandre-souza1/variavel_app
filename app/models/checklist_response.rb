class ChecklistResponse < ApplicationRecord
  belongs_to :checklist
  belongs_to :checklist_item
  has_one_attached :photo # Usa Active Storage com Cloudinary

  validate :comment_required_if_nok

  def comment_required_if_nok
    if status == "nok" && comment.blank? && !photo.attached?
      errors.add(:base, "Comentário ou foto obrigatórios se marcar NOK")
    end
  end
end
