class FleetAvailabilitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :auto_lock_expired_fleet_availabilities
  before_action :set_fleet_availability, only: %i[show destroy lock unlock]
  before_action :require_admin!, only: %i[destroy unlock]
  before_action :require_creator_edit_access!, only: :lock

  def index
    @fleet_availabilities = FleetAvailability.recent.includes(:user)
    @fleet_dashboard = fleet_dashboard
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
    @locking_enabled = FleetAvailability.locking_enabled?
    @editable = @fleet_availability.editable_by?(current_user)
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
    @fleet_availability.destroy_without_lock_version!

    redirect_to fleet_availabilities_path,
                notice: "Disponibilidade removida com sucesso."
  end

  def lock
    unless FleetAvailability.locking_enabled?
      redirect_to @fleet_availability,
                  alert: "A migration de trava ainda precisa ser aplicada."
      return
    end

    @fleet_availability.lock_availability!(current_user)

    redirect_to @fleet_availability,
                notice: "Disponibilidade travada com sucesso."
  end

  def unlock
    unless FleetAvailability.locking_enabled?
      redirect_to @fleet_availability,
                  alert: "A migration de trava ainda precisa ser aplicada."
      return
    end

    @fleet_availability.unlock_availability!

    redirect_to @fleet_availability,
                notice: "Disponibilidade destravada com sucesso."
  end

  private

  def set_fleet_availability
    @fleet_availability = FleetAvailability.find(params[:id])
  end

  def auto_lock_expired_fleet_availabilities
    FleetAvailability.auto_lock_expired!
  end

  def require_creator_edit_access!
    return if @fleet_availability.editable_by?(current_user)

    redirect_to @fleet_availability,
                alert: "Apenas quem iniciou a disponibilidade pode travá-la enquanto ela estiver aberta."
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

  def fleet_dashboard
    {
      total_days: FleetAvailability.count,
      average_coverage: average_coverage,
      locked_count: FleetAvailability.where.not(locked_at: nil).count,
      open_count: FleetAvailability.where(locked_at: nil).count,
      most_used: most_used_plates,
      least_used: least_used_plates,
      maintenance: maintenance_plates,
      most_used_chart: chart_data(most_used_plates),
      least_used_chart: chart_data(least_used_plates),
      maintenance_chart: chart_data(maintenance_plates)
    }
  end

  def average_coverage
    availabilities = FleetAvailability.includes(:fleet_availability_items)

    return 0 unless availabilities.any?

    percentages =
      availabilities.map do |availability|
        next 0 if availability.agreed_quantity.zero?

        available_count =
          availability
          .fleet_availability_items
          .count(&:available?)

        ((available_count.to_f / availability.agreed_quantity) * 100).round
      end

    (percentages.sum.to_f / percentages.size).round
  end

  def most_used_plates
    used_statuses = FleetAvailabilityItem.statuses.values_at(
      "available",
      "special_route"
    )

    FleetAvailabilityItem
      .joins(:plate)
      .where(status: used_statuses)
      .group("plates.id", "plates.placa", "plates.perfil", "plates.tipo")
      .order(Arel.sql("COUNT(fleet_availability_items.id) DESC"))
      .limit(6)
      .pluck(
        "plates.placa",
        "plates.perfil",
        "plates.tipo",
        Arel.sql("COUNT(fleet_availability_items.id)")
      )
  end

  def least_used_plates
    used_statuses = FleetAvailabilityItem.statuses.values_at(
      "available",
      "special_route"
    ).join(",")

    Plate
      .where(tipo: ["Caminhão", "Van"])
      .left_joins(:fleet_availability_items)
      .group("plates.id", "plates.placa", "plates.perfil", "plates.tipo")
      .order(Arel.sql(<<~SQL.squish))
        SUM(
          CASE
            WHEN fleet_availability_items.status IN (#{used_statuses})
            THEN 1
            ELSE 0
          END
        ) ASC,
        COUNT(fleet_availability_items.id) DESC,
        plates.placa ASC
      SQL
      .limit(6)
      .pluck(
        "plates.placa",
        "plates.perfil",
        "plates.tipo",
        Arel.sql(<<~SQL.squish)
          SUM(
            CASE
              WHEN fleet_availability_items.status IN (#{used_statuses})
              THEN 1
              ELSE 0
            END
          )
        SQL
      )
  end

  def maintenance_plates
    FleetAvailabilityItem
      .joins(:plate)
      .where(status: FleetAvailabilityItem.statuses[:unavailable],
             reason: "maintenance")
      .group("plates.id", "plates.placa", "plates.perfil", "plates.tipo")
      .order(Arel.sql("COUNT(fleet_availability_items.id) DESC"))
      .limit(6)
      .pluck(
        "plates.placa",
        "plates.perfil",
        "plates.tipo",
        Arel.sql("COUNT(fleet_availability_items.id)")
      )
  end

  def chart_data(rows)
    rows.each_with_object({}) do |(placa, _perfil, _tipo, count), data|
      data[placa] = count.to_i
    end
  end
end
