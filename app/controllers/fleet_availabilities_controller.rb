class FleetAvailabilitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_fleet_availability, only: :show

  def index
    @fleet_availabilities = current_user.fleet_availabilities.recent
  end

  def new
    date = params[:date].presence || Date.current

    @fleet_availability = FleetAvailability.new(
      date: date,
      agreed_quantity: FleetAvailability.default_agreed_quantity_for(date),
      special_routes: FleetAvailability.default_special_routes_for(date)
    )
  end

  def create
    @fleet_availability = FleetAvailabilities::Creator.call(
      user: current_user,
      date: fleet_availability_params[:date],
      agreed_quantity: fleet_availability_params[:agreed_quantity],
      special_routes: fleet_availability_params[:special_routes]
    )

    redirect_to @fleet_availability,
                notice: "Disponibilidade criada com sucesso."
  rescue ActiveRecord::RecordInvalid => e
    @fleet_availability = FleetAvailability.new(fleet_availability_params)

    flash.now[:alert] = e.record.errors.full_messages.to_sentence

    render :new, status: :unprocessable_entity
  end

  def show
    @items = @fleet_availability
              .fleet_availability_items
              .includes(:plate)
              .ordered
  end

  private

  def set_fleet_availability
    @fleet_availability = current_user
                            .fleet_availabilities
                            .find(params[:id])
  end

  def fleet_availability_params
    params.require(:fleet_availability)
          .permit(
            :date,
            :agreed_quantity,
            special_routes: {}
          )
  end
end
