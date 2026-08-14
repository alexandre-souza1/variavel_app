require "test_helper"

class FleetAvailabilitiesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  fixtures :users, :plates, :fleet_availabilities, :fleet_availability_items

  setup do
    @user = users(:one)
    sign_in @user
    ActionMailer::Base.deliveries.clear
  end

  test "lock sends configured email with pdf attachment" do
    FleetAvailabilityEmailSetting.create!(
      recipients: "gestao@example.com",
      subject: "Disponibilidade %{iso_date}",
      body: "Segue a disponibilidade."
    )

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      patch lock_fleet_availability_path(fleet_availabilities(:one))
    end

    email = ActionMailer::Base.deliveries.last
    assert_equal ["gestao@example.com"], email.to
    assert_equal "Disponibilidade 2026-07-20", email.subject
    assert_equal "disponibilidade_frota_2026-07-20.pdf",
                 email.attachments.first.filename
    assert_redirected_to fleet_availability_path(fleet_availabilities(:one))
  end
end
