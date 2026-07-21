class FleetDimensioningsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_fleet_dimensioning, only: %i[edit update destroy]

  def index
    @fleet_dimensionings = FleetDimensioning.recent
  end

  def new
    @fleet_dimensioning = FleetDimensioning.new
  end

  def create
    @fleet_dimensioning = FleetDimensioning.new(fleet_dimensioning_params)

    if @fleet_dimensioning.save
      redirect_to fleet_dimensionings_path,
                  notice: "Dimensionamento cadastrado com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @fleet_dimensioning.update(fleet_dimensioning_params)
      redirect_to fleet_dimensionings_path,
                  notice: "Dimensionamento atualizado com sucesso."
    else
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

  def fleet_dimensioning_params
    params.require(:fleet_dimensioning)
          .permit(
            :label,
            :start_date,
            :end_date,
            :route_quantity,
            :van_quantity,
            :vespertina_quantity,
            :as_quantity
          )
  end
end
