module Mobile
  class PushDevicesController < ApplicationController
    before_action :authenticate_user!

    def create
      token = params[:token].to_s
      return head :unprocessable_entity if token.blank? || token.bytesize > 2048 || !token.ascii_only?

      session[:mobile_push_binding] ||= SecureRandom.hex(32)
      device = PushDevice.find_or_initialize_by(token: token)
      device.update!(user: current_user, session_binding: session[:mobile_push_binding], last_seen_at: Time.current)
      render json: { user_id: current_user.id.to_s }
    rescue ActiveRecord::RecordNotUnique
      head :conflict # Client retries the registration on the next page visit.
    end

    def destroy
      current_user.push_devices.where(session_binding: session[:mobile_push_binding]).delete_all
      head :no_content
    end

    def open
      notification = current_user.notifications.find(params[:id])
      notification.mark_as_read!
      destination = notification.action_url.to_s
      # Never use a remotely supplied URL from a push payload.
      destination = root_path unless destination.start_with?("/") && !destination.start_with?("//") && !destination.include?("\\")
      redirect_to destination, allow_other_host: false
    end
  end
end
