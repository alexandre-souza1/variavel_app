class ChecklistTrackingSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_settings_access!

  def edit
    @plans = ActionPlan.visible_to(current_user).order(:name)
  end

  def update
    plans = ActionPlan.visible_to(current_user)
    selected_ids = params.require(:checklist_tracking_setting).permit(plan_ids: [])[:plan_ids].to_a.reject(&:blank?)
    visible_ids = plans.pluck(:id)
    selected = plans.where(id: selected_ids).pluck(:id)
    if selected.size != selected_ids.uniq.size
      return redirect_to edit_checklist_tracking_setting_path, status: :see_other, alert: "Selecione apenas planos aos quais você tem acesso."
    end
    ActionPlan.transaction do
      ActionPlan.where(id: visible_ids).where.not(id: selected).update_all(checklist_tracking_visible: false, updated_at: Time.current)
      ActionPlan.where(id: selected).update_all(checklist_tracking_visible: true, updated_at: Time.current)
    end
    redirect_to checklist_occurrences_path, status: :see_other, notice: "Planos de origem atualizados para todos os usuários do módulo."
  end

  private

  def require_settings_access!
    head :forbidden unless current_user.can_manage_checklist_tracking_settings?
  end
end
