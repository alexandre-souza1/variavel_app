module FleetAvailabilityItems
  class ChangeStatus

    def self.call(...)
      new(...).call
    end


    def initialize(
      item:,
      user:,
      status:,
      position:,
      reason: nil,
      observation: nil,
      special_route: nil
    )
      @item = item
      @user = user
      @status = status
      @position = position
      @reason = reason
      @observation = observation
      @special_route = special_route
    end


    def call

      old_status = @item.status


      ActiveRecord::Base.transaction do

        @item.update!(
          update_attributes
        )


        if old_status != @item.status

          FleetAvailabilityChange.create!(
            fleet_availability_item: @item,
            user: @user,
            from_status: old_status,
            to_status: @item.status
          )

        end

      end


      @item

    end


    private


    def update_attributes
      attributes = {
        status: @status,
        position: @position
      }

      attributes[:observation] = @observation unless @observation.nil?

      if @status == "unavailable"
        attributes[:reason] = @reason.presence || "other"
        attributes[:special_route] = nil
      elsif @status == "special_route"
        attributes[:reason] = nil
        attributes[:special_route] = @special_route
      else
        attributes[:reason] = nil
        attributes[:special_route] = nil
      end

      attributes
    end

  end
end
