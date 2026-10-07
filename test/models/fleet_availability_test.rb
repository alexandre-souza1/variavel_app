require "test_helper"

class FleetAvailabilityTest < ActiveSupport::TestCase
  test "exchange count excludes inactive plates" do
    availability = fleet_availabilities(:one)
    plate = plates(:one)

    assert_equal 1, availability.exchange_count

    plate.update!(active: false)

    assert_equal 0, availability.exchange_count
  end
end
