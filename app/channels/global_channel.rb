# app/channels/global_channel.rb
class GlobalChannel < ApplicationCable::Channel
  def subscribed
    if current_user
      stream_from "global_user_#{current_user.id}"
      logger.info "✅ Usuário #{current_user.id} conectado ao GlobalChannel"
    else
      reject
    end
  end

  def unsubscribed
    logger.info "❌ Usuário #{current_user&.id} desconectado do GlobalChannel"
  end
end
