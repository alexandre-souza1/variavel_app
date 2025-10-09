class RemunerationPeriodsController < ApplicationController
  before_action :authenticate_user! # se quiser exigir login
  before_action :set_period, only: %i[show edit update destroy compare export_csv]

  def index
    @periods = RemunerationPeriod.order(start_date: :desc)
  end

  def show; end

  def new
    @period = RemunerationPeriod.new
    build_default_vehicle_remunerations(@period)
  end

  def create
    @period = RemunerationPeriod.new(period_params)
    if @period.save
      redirect_to remuneration_periods_path, notice: "Período criado."
    else
      build_default_vehicle_remunerations(@period)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    build_default_vehicle_remunerations(@period)
  end

  def update
    if @period.update(period_params)
      redirect_to remuneration_periods_path, notice: "Atualizado."
    else
      build_default_vehicle_remunerations(@period)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @period.destroy
    redirect_to remuneration_periods_path, notice: "Removido."
  end

  def compare
    @comparison = @period.comparison_by_category
  end

  def export_csv
    csv = CSV.generate(headers: true) do |csv|
      csv << ["Categoria", "Planejado", "Real", "Diferença"]
      @period.comparison_by_category.each do |row|
        csv << [row[:budget_category].name, row[:planned], row[:real], row[:diff]]
      end
    end
    send_data csv, filename: "remuneration_#{@period.label}.csv"
  end

  private

  def set_period
    @period = RemunerationPeriod.find(params[:id])
  end

  # preenche vehicle_remunerations e os valores por categoria se não existirem
  def build_default_vehicle_remunerations(period)
    VehicleRemuneration::VEHICLE_TYPES.each do |vt|
      vr = period.vehicle_remunerations.detect { |x| x.vehicle_type == vt } ||
           period.vehicle_remunerations.build(vehicle_type: vt)
      BudgetCategory.order(:id).each do |bc|
        vr.remuneration_category_values.detect { |v| v.budget_category_id == bc.id } ||
          vr.remuneration_category_values.build(budget_category: bc)
      end
    end
  end

  def period_params
    params.require(:remuneration_period).permit(
      :label, :start_date, :end_date,
      vehicle_remunerations_attributes: [
        :id, :vehicle_type, :fleet_quantity, :km_remunerated, :_destroy,
        remuneration_category_values_attributes: [:id, :budget_category_id, :value, :_destroy]
      ]
    )
  end
end
