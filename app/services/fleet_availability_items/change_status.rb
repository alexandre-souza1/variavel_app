module FleetAvailabilityItems
  class ChangeStatus

    def self.call(...)
      new(...).call
    end


    def initialize(item:, user:, status:, position:)
      @item = item
      @user = user
      @status = status
      @position = position
    end


    def call

      old_status = @item.status


      ActiveRecord::Base.transaction do

        @item.update!(
          status: @status,
          position: @position
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

  end
end
