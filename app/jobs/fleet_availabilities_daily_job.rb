class FleetAvailabilitiesDailyJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil)
    user = user_id.present? ? User.find_by(id: user_id) : User.order(:id).first
    FleetAvailabilities::DailyOpening.call(user: user)
  end
end
