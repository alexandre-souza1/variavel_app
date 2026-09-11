class PlatesController < ApplicationController
  def index
    @plates = params[:status] == "inactive" ? Plate.inactive : Plate.active

    @plates = @plates.where("placa ILIKE ?", "%#{params[:placa]}%") if params[:placa].present?
    @plates = @plates.where(setor: params[:setor]) if params[:setor].present?
    @plates = @plates.where(tipo: params[:tipo]) if params[:tipo].present?
    @plates = @plates.where(perfil: params[:perfil]) if params[:perfil].present?

    @plates = @plates.order(:placa)
  end

  def new
    @plate = Plate.new
  end

  def show
    @plate = Plate.includes(
      :checklists,
      fleet_availability_items: [:fleet_availability, :fleet_availability_changes]
    ).find(params[:id])

    @observations = plate_observations(@plate)
    @current_observation = @observations.find { |observation| observation[:date]&.to_date == Date.current }
    @mentioned_tasks = tasks_mentioning_plate(@plate)
    @mapa_exits = mapa_exits_for(@plate)
    @most_common_driver = most_common_driver_from(@mapa_exits)
    @latest_availability = @plate.fleet_availability_items
                                  .includes(:fleet_availability)
                                  .max_by { |item| item.fleet_availability.date }
  end

  def create
    @plate = Plate.new(plate_params)
    if @plate.save
      redirect_to plates_path, notice: "Placa criada com sucesso"
    else
      render :new
    end
  end

  def edit
    @plate = Plate.find(params[:id])
  end

  def update
    @plate = Plate.find(params[:id])
    if @plate.update(plate_params)
      redirect_to plates_path, notice: "Placa atualizada com sucesso"
    else
      render :edit
    end
  end

  def destroy
    @plate = Plate.find(params[:id])
    @plate.destroy
    redirect_to plates_path, notice: "Placa removida com sucesso"
  end

  def retire
    @plate = Plate.find(params[:id])
    @plate.retire!
    redirect_to plates_path, notice: "Placa inativada com sucesso. O histórico foi preservado."
  end

  def reactivate
    @plate = Plate.find(params[:id])
    @plate.reactivate!
    redirect_to plates_path(status: "inactive"), notice: "Placa reativada com sucesso."
  end

  def import
    if params[:file].present?
      Plate.import(params[:file])
      redirect_to plates_path, notice: "Placas importadas com sucesso"
    else
      redirect_to plates_path, alert: "Por favor, selecione um arquivo CSV"
    end
  end

  private

  def plate_observations(plate)
    checklist_observations = plate.checklists
      .includes(:user, :checklist_template)
      .where.not(observation: [nil, ""])
      .map do |checklist|
        {
          date: checklist.created_at,
          source: "Checklist",
          text: checklist.observation,
          author: checklist.user&.name,
          path: checklist_path(checklist)
        }
      end

    availability_observations = plate.fleet_availability_items
      .includes(:fleet_availability, :fleet_availability_changes)
      .flat_map do |item|
        current = item.observation.present? ? [{
          date: item.updated_at,
          source: "Disponibilidade",
          text: item.observation,
          author: nil,
          path: fleet_availability_path(item.fleet_availability)
        }] : []

        changes = item.fleet_availability_changes
          .includes(:user)
          .where.not(observation: [nil, ""])
          .map do |change|
            {
              date: change.created_at,
              source: "Histórico da disponibilidade",
              text: change.observation,
              author: change.user&.name,
              path: fleet_availability_path(item.fleet_availability)
            }
          end

        current + changes
      end

    (checklist_observations + availability_observations)
      .sort_by { |observation| observation[:date] }
      .reverse
  end

  def tasks_mentioning_plate(plate)
    term = ActiveRecord::Base.sanitize_sql_like(plate.placa)
    matching_tasks = Task.where(
      "tasks.title ILIKE :term OR tasks.description ILIKE :term",
      term: "%#{term}%"
    )

    comment_task_ids = Comment.where(
      "comments.content ILIKE :term",
      term: "%#{term}%"
    ).select(:task_id)

    task_ids = matching_tasks.pluck(:id) + comment_task_ids.pluck(:task_id)

    Task.where(id: task_ids.uniq)
      .includes(:bucket, :creator, :comments)
      .order(updated_at: :desc)
  end

  def mapa_exits_for(plate)
    normalized_plate = plate.placa.to_s.upcase.gsub(/[^A-Z0-9]/, "")

    Mapa.where(
      "regexp_replace(upper(plate), '[^A-Z0-9]', '', 'g') = ?",
      normalized_plate
    ).includes(:driver).order(created_at: :desc).to_a
  end

  def most_common_driver_from(mapas)
    mapas
      .select { |mapa| mapa.matric_motorista.present? && mapa.matric_motorista != "0" }
      .group_by(&:matric_motorista)
      .max_by { |_matricula, registros| registros.length }
      &.then do |matricula, registros|
        {
          matricula: matricula,
          name: registros.first.driver&.nome,
          count: registros.length
        }
      end
  end

  def plate_params
    params.require(:plate).permit(:placa, :setor, :perfil, :tipo)
  end
end
