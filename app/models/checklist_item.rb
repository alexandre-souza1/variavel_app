class ChecklistItem < ApplicationRecord
  belongs_to :checklist_template
  has_many :checklist_responses, dependent: :restrict_with_error

  default_scope { order(:position) }

  def deletable?
    checklist_responses.none?
  end

end
