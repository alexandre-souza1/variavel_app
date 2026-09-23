class PeopleCycleFeedbacksController < ApplicationController
  before_action :authenticate_user!

  def index
    load_feedbacks
  end

  def create
    result = PeopleCycleImportService.new(file: params[:file], cycle: params[:cycle], user: current_user).call
    redirect_to people_cycle_feedbacks_path(cycle: params[:cycle].to_s.squish.presence || Date.current.year.to_s), notice: "#{result[:count]} resposta(s) importada(s). #{result[:unlinked]} sem vínculo único com cadastro para a IA."
  rescue PeopleCycleImportService::ImportError => error
    flash.now[:alert] = error.message
    load_feedbacks
    render :index, status: :unprocessable_entity
  end

  private

  def load_feedbacks
    @cycles = PeopleCycleFeedback.distinct.order(cycle: :desc).pluck(:cycle)
    @selected_cycle = params[:cycle].to_s
    scope = PeopleCycleFeedback.all
    scope = scope.where(cycle: @selected_cycle) if @selected_cycle.present?
    @query = params[:q].to_s.strip
    scope = scope.where("employee_key LIKE ?", "%#{PeopleCycleFeedback.sanitize_sql_like(PeopleCycleFeedback.normalize(@query))}%") if @query.present?
    @total = scope.count
    @page = [params[:page].to_i, 1].max
    @feedbacks = scope.order(cycle: :desc, employee_name: :asc, stage: :asc).limit(50).offset((@page - 1) * 50)
  end
end
