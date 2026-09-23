class PeopleCycleFeedback < ApplicationRecord
  belongs_to :imported_by, class_name: "User"
  validates :cycle, :employee_name, :employee_key, :stage, :response, presence: true

  def self.normalize(value)
    I18n.transliterate(value.to_s).downcase.squish
  end

  def self.for_identity(identity)
    where(profile: identity.profile, employee_id: identity.record.id,
          employee_key: normalize(identity.name)).order(cycle: :desc, stage: :asc)
  end
end
