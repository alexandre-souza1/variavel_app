class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "workstation@example.com")
  layout "mailer"
end
