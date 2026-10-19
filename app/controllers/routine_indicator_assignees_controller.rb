class RoutineIndicatorAssigneesController < ApplicationController
  before_action :authenticate_user!

  def update
    value = RoutineValue.where(routine_id: Routine.visible_to(current_user).select(:id))
      .find(params[:routine_value_id])
    template = value.routine.routine_template
    unless template.action_plan && template.manageable_by?(current_user)
      return render json: { errors: ["Você não tem permissão para alterar os responsáveis deste indicador."] }, status: :forbidden
    end

    ids = params.require(:routine_indicator)[:user_ids]
    unless ids.is_a?(Array) && ids.all? { |id| id.to_s.match?(/\A[0-9]+\z/) }
      return render json: { errors: ["Selecione responsáveis válidos."] }, status: :unprocessable_entity
    end

    ids = ids.map(&:to_i).uniq
    users = User.where(id: ids).to_a
    if users.size != ids.size
      return render json: { errors: ["Um dos responsáveis selecionados não foi encontrado."] }, status: :unprocessable_entity
    end

    value.routine_indicator.update!(users: users)
    render json: { user_ids: users.map(&:id) }
  rescue ActiveRecord::RecordInvalid => error
    render json: { errors: error.record.errors.full_messages }, status: :unprocessable_entity
  end
end
