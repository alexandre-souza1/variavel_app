class FleetDimensioningsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_fleet_dimensioning, only: %i[edit update destroy]

  def index
    @fleet_dimensionings = FleetDimensioning.recent
  end

  def new
    @fleet_dimensioning = FleetDimensioning.new
    @fleet_dimensioning.build_standard_plate_slots(standard_plate_slot_quantity)
  end

  def create
    @fleet_dimensioning = FleetDimensioning.new(fleet_dimensioning_params)

    if @fleet_dimensioning.save
      redirect_to fleet_dimensionings_path,
                  notice: "Dimensionamento cadastrado com sucesso."
    else
      @fleet_dimensioning.build_standard_plate_slots(standard_plate_slot_quantity)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @fleet_dimensioning.build_standard_plate_slots(standard_plate_slot_quantity)
  end

  def update
    if @fleet_dimensioning.update(fleet_dimensioning_params)
      redirect_to fleet_dimensionings_path,
                  notice: "Dimensionamento atualizado com sucesso."
    else
      @fleet_dimensioning.build_standard_plate_slots(standard_plate_slot_quantity)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @fleet_dimensioning.destroy

    redirect_to fleet_dimensionings_path,
                notice: "Dimensionamento removido com sucesso."
  end

  private

  def set_fleet_dimensioning
    @fleet_dimensioning = FleetDimensioning.find(params[:id])
  end

  def standard_plate_slot_quantity
    [
      @fleet_dimensioning.route_quantity.to_i,
      Plate.where(setor: "ROTA").count,
      FleetDimensioning::STANDARD_PLATE_SLOTS
    ].max
  end

  def fleet_dimensioning_params
    permitted_params =
      params.require(:fleet_dimensioning)
            .permit(
              :label,
              :start_date,
              :end_date,
              :route_quantity,
              :van_quantity,
              :vespertina_quantity,
              :as_quantity,
              fleet_dimensioning_standard_plates_attributes: [
                :id,
                :position,
                :plate_id,
                :_destroy
              ]
            )

    standard_plate_attributes =
      permitted_params[:fleet_dimensioning_standard_plates_attributes]

    standard_plate_attributes&.each_value do |attributes|
      next if attributes[:plate_id].present? || attributes[:id].blank?

      attributes[:_destroy] = "1"
    end

    permitted_params
  end
end
