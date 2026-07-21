class FleetAvailabilityChange < ApplicationRecord

  belongs_to :fleet_availability_item
  belongs_to :user


  enum :from_status, {
    available: 0,
    exchange: 1,
    unavailable: 2
  }, prefix: true


  enum :to_status, {
    available: 0,
    exchange: 1,
    unavailable: 2
  }, prefix: true

end
