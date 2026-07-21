class FleetAvailabilityItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_item

  def update

    item = FleetAvailabilityItems::ChangeStatus.call(
      item: @item,
      user: current_user,
      status: item_params[:status],
      position: item_params[:position],
      reason: item_params[:reason],
      observation: item_params[:observation],
      special_route: item_params[:special_route]
    )

    render json: {
      id: item.id,
      status: item.status,
      status_label: item.status_label,
      reason: item.reason,
      reason_label: item.reason_label,
      observation: item.observation,
      position: item.position,
      special_route: item.special_route,
      special_route_label: item.special_route_label
    }

  rescue ActiveRecord::RecordInvalid

    head :unprocessable_entity

  end


  private


  def set_item
    @fleet_availability =
      current_user.fleet_availabilities.find(params[:fleet_availability_id])
    @item = @fleet_availability.fleet_availability_items.find(params[:id])
  end


  def item_params
    params.require(:fleet_availability_item)
          .permit(:status, :position, :reason, :observation, :special_route)
  end

end
