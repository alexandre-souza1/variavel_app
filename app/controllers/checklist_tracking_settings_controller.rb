class ChecklistTrackingSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_settings_access!

  def edit
    return redirect_to checklist_occurrences_path(tracking_filters.merge(settings: '1')), status: :see_other unless turbo_frame_request?

    @plans = ActionPlan.visible_to(current_user).order(:name)
    render partial: 'form'
  end

  def update
    plans = ActionPlan.visible_to(current_user)
    selected_ids = params.require(:checklist_tracking_setting).permit(plan_ids: [])[:plan_ids].to_a.reject(&:blank?)
    visible_ids = plans.pluck(:id)
    selected = plans.where(id: selected_ids).pluck(:id)
    if selected.size != selected_ids.uniq.size
      @error = "Selecione apenas planos aos quais você tem acesso."
      if turbo_frame_request?
        @plans = plans.order(:name)
        return render partial: 'form', status: :unprocessable_entity
      end
      return redirect_to edit_checklist_tracking_setting_path(context: tracking_filters), status: :see_other, alert: @error
    end
    ActionPlan.transaction do
      ActionPlan.where(id: visible_ids).where.not(id: selected).update_all(checklist_tracking_visible: false, updated_at: Time.current)
      ActionPlan.where(id: selected).update_all(checklist_tracking_visible: true, updated_at: Time.current)
    end
    destination = checklist_occurrences_path(tracking_filters)
    message = "Planos de origem atualizados para todos os usuários do módulo."
    if turbo_frame_request?
      flash[:notice] = message
      render partial: 'saved', locals: { destination: destination }
    else
      redirect_to destination, status: :see_other, notice: message
    end
  end

  private

  def tracking_filters
    params.fetch(:context, ActionController::Parameters.new).permit(*ChecklistOccurrencesController::FILTER_KEYS, :candidate_page).to_h
  end

  def require_settings_access!
    head :forbidden unless current_user.can_manage_checklist_tracking_settings?
  end
end
