class ParkingLayoutsController < ApplicationController
  before_action :require_parking_admin!, only: :update

  def show
    @layout = ParkingLayout.current
    @slots = ParkingLayout::SLOTS.index_by { |slot| slot.fetch("number") }
    @assignments = @layout.visible_assignments
    @return_path = params[:origem] == "az" ? az_consultas_new_path : consultas_new_path
    @available_plates = @layout.available_plates if current_user&.admin?
  end

  def update
    unless params[:assignments].is_a?(ActionController::Parameters) && params[:lock_version].to_s.match?(/\A\d+\z/) && params[:assignments].keys.sort == ParkingLayout::SLOT_KEYS.sort
      return render json: { error: "Distribuição inválida. Recarregue a página e tente novamente." }, status: :unprocessable_entity
    end

    layout = ParkingLayout.current
    if layout.lock_version != params[:lock_version].to_i
      return render_conflict
    end

    layout.assignments = params[:assignments].permit(*ParkingLayout::SLOT_KEYS).to_h
    layout.updated_by = current_user
    layout.lock_version = 1 if layout.new_record?
    if layout.save
      render json: { message: "Distribuição do pátio salva.", lock_version: layout.lock_version }
    else
      render json: { error: layout.errors.full_messages.join(" ") }, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique
    render_conflict
  end

  private

  def require_parking_admin!
    render json: { error: "Apenas administradores podem alterar o pátio." }, status: :forbidden unless current_user&.admin?
  end

  def render_conflict
    render json: { error: "Outro administrador atualizou o pátio. Recarregue a página antes de editar novamente." }, status: :conflict
  end
end
