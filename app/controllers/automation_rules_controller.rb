class AutomationRulesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_access
  before_action :set_rule, only: %i[show edit update execute toggle]

  def index
    rules = AutomationRule.visible_to(current_user)
    @total_count, @active_count = rules.count, rules.where(enabled: true).count
    @rules = rules.includes(:user).order(created_at: :desc).limit(100)
    @runs = AutomationRun.where(automation_rule_id: rules.select(:id)).includes(:automation_rule, :actor).order(created_at: :desc).limit(50)
  end

  def show
    @runs = @rule.automation_runs.includes(:actor).order(created_at: :desc).limit(50)
    load_preview
  end

  def new
    @rule = AutomationRule.new(user: current_user, source_key: "invoices", operation: "sum", period: "month",
      action_key: "update_indicator", filters: {}, action_config: {})
    load_options
  end

  def edit
    load_options
  end

  def create
    @rule = AutomationRule.new(rule_params.merge(user: current_user, enabled: false))
    if params[:intent] == "preview"
      load_preview
      load_options
      render :new, status: @preview_error ? :unprocessable_entity : :ok
    elsif @rule.save
      saved_response("Automação criada e pausada. Confira a prévia e ative quando desejar.", automation_rules_path)
    else
      load_options
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if params[:intent] == "preview"
      @rule.assign_attributes(rule_params.merge(enabled: false))
      load_preview
      load_options
      render :edit, status: @preview_error ? :unprocessable_entity : :ok
    else
      @rule.with_lock do
        if @rule.update(rule_params.merge(enabled: false))
          saved_response("Configuração salva e pausada. Confira a prévia antes de reativar.", automation_rule_path(@rule))
        else
          load_options
          render :edit, status: :unprocessable_entity
        end
      end
    end
  end

  def execute
    run = Automations::Runner.call(@rule, actor: current_user)
    redirect_to @rule, notice: run.message
  end

  def toggle
    @rule.with_lock do
      if @rule.enabled?
        # Pausing must remain possible after permissions or a destination change.
        @rule.update_columns(enabled: false, next_run_at: nil, updated_at: Time.current)
        redirect_to @rule, notice: "Automação pausada."
      elsif @rule.update(enabled: true)
        redirect_to @rule, notice: "Automação ativada."
      else
        redirect_to @rule, alert: @rule.errors.full_messages.to_sentence
      end
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to @rule, alert: "O indicador já possui outra automação ativa."
  end

  private

  def saved_response(message, drawer_destination)
    if turbo_frame_request?
      flash[:notice] = message
      render partial: "drawer_saved", locals: { destination: drawer_destination }
    else
      redirect_to @rule, notice: message
    end
  end

  def authorize_access
    redirect_to root_path, alert: "Este perfil não possui acesso às automações." if current_user.mechanical? || !current_user.active?
  end

  def set_rule
    @rule = AutomationRule.visible_to(current_user).find(params[:id])
  end

  def load_options
    owner = @rule.user
    @sources = Automations::Catalog.sources_for(owner)
    @categories = Automations::Configuration.categories_for(owner).order(:name)
    @sectors = owner.admin? || owner.sector_finance? ? BudgetCategory.sectors.keys : owner.budget_sectors
    @plans = ActionPlan.visible_to(owner).order(:name)
    @buckets = Automations::Configuration.buckets_for(owner).includes(:action_plan).order(:position)
    @templates = RoutineTemplate.visible_to(owner).order(:name)
    @indicators = RoutineIndicator.active.joins(:routine_category)
      .where(routine_categories: { routine_template_id: @templates.select(:id) })
      .where(value_type: %i[integer decimal currency]).includes(:routine_category).order(:name)
  end

  def load_preview
    @preview = Automations::Preview.call(@rule)
  rescue Automations::Invalid => error
    @preview_error = error.message
  end

  def rule_params
    raw = params.require(:automation_rule)
    normalized_ids = if raw[:filters].respond_to?(:key?) && raw[:filters].key?(:budget_category_ids)
      Automations::Configuration.category_ids({ "budget_category_ids" => raw[:filters][:budget_category_ids], "budget_category_id" => raw[:filters][:budget_category_id] })
    end
    permitted = raw.permit(:name, :description, :source_key, :operation, :period,
      :condition_operator, :condition_value, :action_key, :schedule, :execution_hour, :weekday, :month_day,
      filters: [:sector, :budget_category_id, :status, :action_plan_id, :only_mine, { budget_category_ids: [] }],
      action_config: %i[routine_template_id routine_indicator_id overwrite_manual title body bucket_id due_in_days])
    permitted[:filters][:budget_category_ids] = normalized_ids if normalized_ids
    permitted
  rescue Automations::Invalid => error
    raise ActionController::BadRequest, error.message
  end
end
