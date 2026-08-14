class FleetAvailabilityEmailSetting < ApplicationRecord
  DEFAULT_SUBJECT = "Disponibilidade da frota - %{date}".freeze
  DEFAULT_BODY = "Segue em anexo a disponibilidade da frota do dia %{date}.".freeze

  has_one_attached :signature_image

  validates :subject, presence: true
  validate :recipients_are_valid
  validate :signature_image_is_valid

  def self.current
    first_or_create!(
      enabled: true,
      subject: DEFAULT_SUBJECT,
      body: DEFAULT_BODY
    )
  end

  def recipient_list
    parse_emails(recipients)
  end

  def cc_list
    parse_emails(cc)
  end

  def bcc_list
    parse_emails(bcc)
  end

  def deliverable?
    enabled? && recipient_list.any?
  end

  def subject_for(fleet_availability)
    interpolate(subject, fleet_availability)
  end

  def body_for(fleet_availability)
    interpolate(body, fleet_availability)
  end

  private

  def parse_emails(value)
    value
      .to_s
      .split(/[\s,;]+/)
      .map(&:strip)
      .reject(&:blank?)
      .uniq
  end

  def recipients_are_valid
    {
      recipients: recipient_list,
      cc: cc_list,
      bcc: bcc_list
    }.each do |attribute, emails|
      emails.each do |email|
        next if URI::MailTo::EMAIL_REGEXP.match?(email)

        errors.add(attribute, "#{email} não é um e-mail válido")
      end
    end
  end

  def interpolate(template, fleet_availability)
    template.to_s % {
      date: I18n.l(fleet_availability.date),
      iso_date: fleet_availability.date.iso8601
    }
  rescue KeyError
    template.to_s
  end

  def signature_image_is_valid
    return unless signature_image.attached?
    return if signature_image.content_type.in?(%w[image/png image/jpeg image/gif image/webp])

    errors.add(:signature_image, "precisa ser uma imagem PNG, JPG, GIF ou WEBP")
  end
end
