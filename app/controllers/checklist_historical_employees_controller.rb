class ChecklistHistoricalEmployeesController < ApplicationController
  include TaskAccess
  before_action :authenticate_user!
  before_action :require_access!
  before_action :set_context

  def new
    @registration = Employees::HistoricalRegistration.new
    render partial: 'modal' if request.xhr?
  end

  def create
    @registration = Employees::HistoricalRegistration.new(params.require(:historical_employee).permit(:nome, :matricula, :profile, :starts_on, :ends_on))
    if @registration.save(user: current_user)
      message = 'Ex-colaborador cadastrado como inativo. Selecione-o na ação ou use a identificação em lote para reconhecer suas outras tarefas.'
      respond_to do |format|
        format.json { render json: { message: message, employee: { id: @registration.employee.id, label: @registration.employee.checklist_identity_label } }, status: :created }
        format.html { redirect_to checklist_occurrences_path(@tracking_filters), status: :see_other, notice: message }
      end
    else
      respond_to do |format|
        format.json { render json: { html: render_to_string(partial: 'modal', formats: [:html]) }, status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  private

  def require_access!
    head :forbidden unless current_user.can_view_checklist_tracking? && current_user.can_manage_employees?
  end

  def set_context
    @task = find_accessible_task(params[:task_id]) if params[:task_id].present?
    @tracking_filters = params.permit(:year, :action_plan_id, :employee_sector).to_h.merge(display: 'review')
    @profiles = Employees::HistoricalRegistration::PROFILES.filter_map do |value, (label, sector, _)|
      [label, value] if current_user.employee_sectors.include?(sector)
    end
  end
end
