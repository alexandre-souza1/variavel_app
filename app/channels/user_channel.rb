class UserChannel < ApplicationCable::Channel
  def subscribed
    if params[:user_id]
      stream_from "user_#{params[:user_id]}"
      logger.info "✅ Usuário #{params[:user_id]} inscrito no UserChannel"
    else
      reject
    end
  end

  def unsubscribed
    logger.info "❌ Usuário #{params[:user_id]} desinscrito do UserChannel"
  end
end
