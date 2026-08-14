class FleetAvailabilityMailer < ApplicationMailer
  def locked_availability(fleet_availability, actor)
    @fleet_availability = fleet_availability
    @actor = actor
    @setting = FleetAvailabilityEmailSetting.current
    @body = @setting.body_for(@fleet_availability)

    attach_signature_image

    attachments[pdf_filename] = {
      mime_type: "application/pdf",
      content: FleetAvailabilityPdf.new(@fleet_availability).render
    }

    mail(
      to: @setting.recipient_list,
      cc: @setting.cc_list,
      bcc: @setting.bcc_list,
      subject: @setting.subject_for(@fleet_availability)
    )
  end

  private

  def pdf_filename
    "disponibilidade_frota_#{@fleet_availability.date}.pdf"
  end

  def attach_signature_image
    return unless @setting.signature_image.attached?

    @signature_filename = @setting.signature_image.filename.to_s
    attachments.inline[@signature_filename] = {
      mime_type: @setting.signature_image.content_type,
      content: @setting.signature_image.download
    }
  end
end
