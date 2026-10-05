class ActionPlanRoutineTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_plan
  before_action :require_management, except: :show

  def new
    return redirect_to action_plan_gerot_template_path(@action_plan) if @action_plan.gerot_template

    @routine_template = @action_plan.build_gerot_template(name: "GEROT — #{@action_plan.name}", sector: @action_plan.sector)
    render "routine_templates/new"
  end

  def create
    @routine_template = Routines::PlanTemplateBuilder.call(action_plan: @action_plan, attributes: template_params.to_h)
    redirect_to action_plan_gerot_template_path(@action_plan), notice: "Modelo criado com uma categoria para cada bucket. Cadastre os indicadores para gerar os GEROTs."
  rescue ActiveRecord::RecordInvalid => error
    @routine_template = if error.record.is_a?(RoutineTemplate)
      error.record
    else
      @action_plan.build_gerot_template(template_params)
    end
    @routine_template.errors.add(:base, error.record.errors.full_messages.to_sentence) unless error.record == @routine_template
    render "routine_templates/new", status: :unprocessable_entity
  end

  def show
    @routine_template = @action_plan.gerot_template || raise(ActiveRecord::RecordNotFound)
    @can_manage_template = @action_plan.manageable_by?(current_user)
    render "routine_templates/show"
  end

  def edit
    @routine_template = @action_plan.gerot_template || raise(ActiveRecord::RecordNotFound)
    render "routine_templates/edit"
  end

  def update
    @routine_template = @action_plan.gerot_template || raise(ActiveRecord::RecordNotFound)
    if @routine_template.update(template_params)
      redirect_to action_plan_gerot_template_path(@action_plan), notice: "Modelo do plano atualizado."
    else
      render "routine_templates/edit", status: :unprocessable_entity
    end
  end

  private

  def set_plan
    @action_plan = ActionPlan.visible_to(current_user).find(params[:action_plan_id])
  end

  def require_management
    head :forbidden unless @action_plan.manageable_by?(current_user)
  end

  def template_params
    params.require(:routine_template).permit(:name, :description, :active)
  end
end
