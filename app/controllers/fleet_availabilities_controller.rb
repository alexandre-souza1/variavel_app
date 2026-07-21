class FleetAvailabilitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_fleet_availability, only: %i[show destroy]
  before_action :require_admin!, only: :destroy

  def index
    @fleet_availabilities = FleetAvailability.all
  end

  def new
    date = params[:date].presence || Date.current
    @dimensioning_period = FleetAvailability.dimensioning_period_for(date)
    @dimensioning_quantities = dimensioning_quantities(@dimensioning_period)

    @fleet_availability = FleetAvailability.new(
      date: date,
      agreed_quantity: FleetAvailability.default_dimensioning_quantity_for(date),
      special_routes: FleetAvailability.default_special_routes_for(date)
    )
  end

  def create
    dimensioning_period = FleetAvailability.dimensioning_period_for(
      fleet_availability_params[:date]
    )

    unless dimensioning_period
      @fleet_availability = FleetAvailability.new(fleet_availability_params)
      @dimensioning_period = nil
      @dimensioning_quantities = {}

      flash.now[:alert] =
        "Não há dimensionamento cadastrado para o período informado."

      render :new, status: :unprocessable_entity
      return
    end

    @fleet_availability = FleetAvailabilities::Creator.call(
      user: current_user,
      date: fleet_availability_params[:date],
      agreed_quantity: dimensioning_period.route_quantity,
      special_routes: dimensioning_period.special_routes,
      copy_previous_day: ActiveModel::Type::Boolean.new.cast(
        fleet_availability_params[:copy_previous_day]
      )
    )

    redirect_to @fleet_availability,
                notice: "Disponibilidade criada com sucesso."
  rescue ActiveRecord::RecordInvalid => e
    @fleet_availability = FleetAvailability.new(fleet_availability_params)
    @dimensioning_period = FleetAvailability.dimensioning_period_for(
      fleet_availability_params[:date]
    )
    @dimensioning_quantities = dimensioning_quantities(@dimensioning_period)

    flash.now[:alert] = e.record.errors.full_messages.to_sentence

    render :new, status: :unprocessable_entity
  end

  def show
    @items = @fleet_availability
              .fleet_availability_items
              .includes(:plate)
              .ordered
    @dimensioning = FleetAvailability.dimensioning_period_for(@fleet_availability.date)
    @standard_plate_by_position =
      @dimensioning&.standard_plate_by_position || {}

    respond_to do |format|
      format.html
      format.pdf do
        pdf = FleetAvailabilityPdf.new(@fleet_availability)

        send_data pdf.render,
                  filename: "disponibilidade_frota_#{@fleet_availability.date}.pdf",
                  type: "application/pdf",
                  disposition: "inline"
      end
    end
  end

  def destroy
    @fleet_availability.destroy

    redirect_to fleet_availabilities_path,
                notice: "Disponibilidade removida com sucesso."
  end

  private

  def set_fleet_availability
    @fleet_availability = FleetAvailability.find(params[:id])
  end

  def fleet_availability_params
    params.require(:fleet_availability)
          .permit(
            :date,
            :copy_previous_day
          )
  end

  def dimensioning_quantities(period)
    return {
      "ROTA" => 0,
      "VAN" => 0,
      "VESP" => 0,
      "AS" => 0
    } unless period

    {
      "ROTA" => period.route_quantity.to_i,
      "VAN" => period.van_quantity.to_i,
      "VESP" => period.vespertina_quantity.to_i,
      "AS" => period.as_quantity.to_i
    }
  end
end
