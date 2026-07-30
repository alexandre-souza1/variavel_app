class RoutineChannel < ApplicationCable::Channel
  def subscribed
    @routine = Routine.find(params[:routine_id])
    @user = User.find(params[:user_id])

    @editing_routine_value_ids = Set.new

    stream_for @routine
  rescue ActiveRecord::RecordNotFound
    reject
  end

  def start_editing(data)
    routine_value_id =
      data["routine_value_id"].to_i

    @editing_routine_value_ids.add(
      routine_value_id
    )

    broadcast_presence(
      "editing_started",
      routine_value_id
    )
  end

  def editing_heartbeat(data)
    broadcast_presence(
      "editing_heartbeat",
      data["routine_value_id"]
    )
  end

  def stop_editing(data)
    routine_value_id =
      data["routine_value_id"].to_i

    @editing_routine_value_ids.delete(
      routine_value_id
    )

    broadcast_presence(
      "editing_stopped",
      routine_value_id
    )
  end

  def unsubscribed
    @editing_routine_value_ids.each do |routine_value_id|

      broadcast_presence(
        "editing_stopped",
        routine_value_id
      )

    end
  end

  private

  def broadcast_presence(type, routine_value_id)
    self.class.broadcast_to(
      @routine,
      {
        type: type,
        routine_value_id: routine_value_id.to_i,
        user_id: @user.id,
        user_name: user_name
      }
    )
  end

  def user_name
    return @user.name if @user.respond_to?(:name) &&
                        @user.name.present?

    return @user.full_name if @user.respond_to?(:full_name) &&
                              @user.full_name.present?

    return @user.email if @user.respond_to?(:email) &&
                          @user.email.present?

    "Usuário ##{@user.id}"
  end
end
