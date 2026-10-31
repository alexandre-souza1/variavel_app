class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: %i[read destroy]

  def preferences
    preferences = params.require(:user).permit(:daily_summary_enabled)
    current_user.update!(preferences)
    enabled = current_user.daily_summary_enabled?
    message = enabled ? "Resumo do dia ativado para as 8h (Brasília)." : "Resumo do dia desativado."

    respond_to do |format|
      format.json do
        render json: { daily_summary_enabled: enabled, next_delivery_at: current_user.daily_summary_next_run_at,
                       message: message }
      end
      format.html { redirect_back fallback_location: root_path, notice: message }
    end
  end

  def read
    @notification.mark_as_read!

    redirect_to notification_redirect_url,
                allow_other_host: false
  end

  def destroy
    @notification.skip_destroy_broadcast = true
    @notification.destroy!

    respond_to do |format|
      format.html do
        redirect_back fallback_location: root_path,
                      notice: "Notificação apagada."
      end
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("notification_#{@notification.id}")
      end
      format.json do
        render json: {
          id: @notification.id,
          unread_count: current_user.notifications.unread.count,
          notification_count: current_user.notifications.count
        }
      end
    end
  end

  def destroy_all
    current_user.notifications.delete_all

    respond_to do |format|
      format.html do
        redirect_back fallback_location: root_path,
                      notice: "Notificações apagadas."
      end
      format.json do
        render json: { unread_count: 0, notification_count: 0 }
      end
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
