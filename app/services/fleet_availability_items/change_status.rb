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
      special_route: nil,
      supplier_id: nil,
      confirm_non_van_plate: false
    )
      @item = item
      @user = user
      @status = status
      @position = position
      @reason = reason
      @observation = observation
      @special_route = special_route
      @supplier_id = supplier_id
      @confirm_non_van_plate = confirm_non_van_plate
    end


    def call

      old_status = @item.status
      old_supplier_id = @item.supplier_id


      ActiveRecord::Base.transaction do

        @item.update!(
          update_attributes
        )


        if old_status != @item.status || old_supplier_id != @item.supplier_id

          FleetAvailabilityChange.create!(
            fleet_availability_item: @item,
            user: @user,
            from_status: old_status,
            to_status: @item.status,
            reason: @item.reason,
            supplier: @item.supplier,
            observation: @observation
          )

        end

      end


      @item

    end


    private


    def update_attributes
      attributes = {
        status: @status,
        position: @position,
        confirm_non_van_plate: @confirm_non_van_plate
      }

      attributes[:observation] = @observation unless @observation.nil?

      if @status == "unavailable"
        attributes[:supplier_id] = @supplier_id unless @supplier_id.nil?
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
