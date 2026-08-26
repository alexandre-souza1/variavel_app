class FleetDimensioningsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_fleet_dimensioning, only: %i[edit update destroy]

  def index
    @fleet_dimensionings = FleetDimensioning.recent
  end

  def new
    @fleet_dimensioning = FleetDimensioning.new
    @fleet_dimensioning.build_standard_plate_slots(standard_plate_slot_quantity)
    @fleet_dimensioning.build_special_route_slots
  end

  def create
    permitted_params = fleet_dimensioning_params
    @fleet_dimensioning = FleetDimensioning.new(permitted_params)

    if @fleet_dimensioning.save
      persist_special_route_standard_plates!(permitted_params)
      redirect_to fleet_dimensionings_path,
                  notice: "Dimensionamento cadastrado com sucesso."
    else
      @fleet_dimensioning.build_standard_plate_slots(standard_plate_slot_quantity)
      @fleet_dimensioning.build_special_route_slots
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @fleet_dimensioning.build_standard_plate_slots(standard_plate_slot_quantity)
    @fleet_dimensioning.build_special_route_slots
  end

  def update
    permitted_params = fleet_dimensioning_params

    if @fleet_dimensioning.update(permitted_params)
      persist_special_route_standard_plates!(permitted_params)
      redirect_to fleet_dimensionings_path,
                  notice: "Dimensionamento atualizado com sucesso."
    else
      @fleet_dimensioning.build_standard_plate_slots(standard_plate_slot_quantity)
      @fleet_dimensioning.build_special_route_slots
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
    fleet_params = params.require(:fleet_dimensioning)
    permitted_params = fleet_params.permit(
      :label,
      :start_date,
      :end_date,
      :route_quantity,
      :van_quantity,
      :vespertina_quantity,
      :as_quantity
    )

    # Rails only permits numeric indexes by default for nested attributes.
    # The special-route slots use textual indexes such as "special_van".
    raw_attributes = fleet_params[:fleet_dimensioning_standard_plates_attributes]
    if raw_attributes.respond_to?(:to_h)
      nested_attributes = raw_attributes.to_unsafe_h.each_with_object({}) do |(index, attributes), result|
        result[index] = ActionController::Parameters
          .new(attributes)
          .permit(:id, :position, :plate_id, :special_route, :_destroy)
          .to_h
      end

      # Mark only the already-whitelisted nested structure as permitted. This
      # also prevents ActiveRecord#update from rejecting textual indexes such
      # as "special_van" as unfiltered parameters.
      permitted_params[:fleet_dimensioning_standard_plates_attributes] =
        ActionController::Parameters.new(nested_attributes).permit!
    end

    standard_plate_attributes =
      permitted_params[:fleet_dimensioning_standard_plates_attributes]

    standard_plate_attributes&.each_value do |attributes|
      plate_id = attributes[:plate_id].presence || attributes["plate_id"].presence
      id = attributes[:id].presence || attributes["id"].presence
      next if plate_id.present? || id.blank?

      attributes[:_destroy] = "1"
    end

    permitted_params.to_h
  end

  def persist_special_route_standard_plates!(permitted_params)
    attributes = permitted_params[:fleet_dimensioning_standard_plates_attributes]
    return if attributes.blank?

    attributes.to_h.each_value do |route_attributes|
      route = route_attributes["special_route"].presence || route_attributes[:special_route].presence
      next if route.blank?

      plate_id = route_attributes["plate_id"].presence || route_attributes[:plate_id].presence
      standard_plate = @fleet_dimensioning
                       .fleet_dimensioning_standard_plates
                       .find_or_initialize_by(special_route: route)

      if plate_id.present?
        standard_plate.update!(plate_id: plate_id, position: nil)
      elsif standard_plate.persisted?
        standard_plate.destroy!
      end
    end
  end
end
