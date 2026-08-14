require "test_helper"

class FleetAvailabilityEmailSettingTest < ActiveSupport::TestCase
  fixtures []

  test "parses recipients from common separators" do
    setting = FleetAvailabilityEmailSetting.new(
      recipients: "one@example.com; two@example.com\none@example.com",
      cc: "copy@example.com, other@example.com",
      bcc: "",
      subject: "Disponibilidade %{date}",
      body: "Corpo"
    )

    assert_equal ["one@example.com", "two@example.com"], setting.recipient_list
    assert_equal ["copy@example.com", "other@example.com"], setting.cc_list
    assert setting.valid?
  end

  test "rejects invalid emails" do
    setting = FleetAvailabilityEmailSetting.new(
      recipients: "destinatario-invalido",
      subject: "Disponibilidade %{date}",
      body: "Corpo"
    )

    assert_not setting.valid?
    assert_includes setting.errors[:recipients],
                    "destinatario-invalido não é um e-mail válido"
  end
end
