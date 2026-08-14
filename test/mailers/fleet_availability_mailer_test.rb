require "test_helper"

class FleetAvailabilityMailerTest < ActionMailer::TestCase
  fixtures :users, :plates, :fleet_availabilities, :fleet_availability_items

  test "locked availability email includes pdf attachment" do
    FleetAvailabilityEmailSetting.create!(
      recipients: "gestao@example.com",
      cc: "copia@example.com",
      subject: "Disponibilidade %{iso_date}",
      body: "Segue o PDF de %{date}."
    )

    email = FleetAvailabilityMailer.locked_availability(
      fleet_availabilities(:one),
      users(:one)
    )

    assert_equal ["gestao@example.com"], email.to
    assert_equal ["copia@example.com"], email.cc
    assert_equal "Disponibilidade 2026-07-20", email.subject
    assert_equal 1, email.attachments.size
    assert_equal "disponibilidade_frota_2026-07-20.pdf",
                 email.attachments.first.filename
    assert_equal "application/pdf", email.attachments.first.mime_type
  end
end
