class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: %i[read destroy]

  def read
    @notification.mark_as_read!

    redirect_to notification_redirect_url,
                allow_other_host: false
  end

  def destroy
    @notification.destroy!

    respond_to do |format|
      format.html do
        redirect_back fallback_location: root_path,
                      notice: "Notificação apagada."
      end
      format.turbo_stream { head :ok }
    end
  end

  private

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  end

  def notification_redirect_url
    @notification.action_url.presence || root_path
  end
end
