class FleetAvailabilitiesDailyJob < ApplicationJob
  queue_as :default

  def perform
    user = User.order(:id).first

    result = FleetAvailabilities::DailyOpening.call(user: user)

    Rails.logger.info(
      "[FleetAvailabilitiesDailyJob] " \
      "availability_id=#{result.availability&.id} " \
      "date=#{result.availability&.date} " \
      "skipped_reason=#{result.skipped_reason} " \
      "locked_count=#{result.locked_count}"
    )
  end
end
