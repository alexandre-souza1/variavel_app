class ChecklistItem < ApplicationRecord
  belongs_to :checklist_template
  default_scope { order(:position) }
end
