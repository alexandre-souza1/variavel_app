class ChecklistItem < ApplicationRecord
  belongs_to :checklist_template

  has_many :checklist_responses, dependent: :destroy

  default_scope { order(:position) }

  def deletable?
    checklist_responses.none?
  end

  before_destroy :prevent_destroy_if_has_responses

  private

  def prevent_destroy_if_has_responses
    if checklist_responses.exists? && !destroying_template?
      errors.add(:base, "Pergunta possui respostas e não pode ser excluída.")
      throw(:abort)
    end
  end

  def destroying_template?
    checklist_template.destroyed_by_association.present?
  end
end
