class FleetAvailabilityItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_item

  def update

    if @item.update(item_params)

      FleetAvailabilityItems::ChangeStatus.call(
        item: @item,
        user: current_user,
        status: item_params[:status],
        position: item_params[:position]
      )

      head :ok

    else

      head :unprocessable_entity

    end

  end


  private


  def set_item
    @item = FleetAvailabilityItem.find(params[:id])
  end


  def item_params
    params.require(:fleet_availability_item)
          .permit(:status, :position, :reason, :observation)
  end

end
