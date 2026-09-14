class HiddenActionPlan < ApplicationRecord
  belongs_to :user
  belongs_to :action_plan

  validates :action_plan_id, uniqueness: { scope: :user_id }
end
