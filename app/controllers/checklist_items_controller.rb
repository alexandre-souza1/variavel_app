class ChecklistItemsController < ApplicationController
  before_action :authenticate_user!

  def create
    template = ChecklistTemplate.find(params[:checklist_template_id])
    item = template.checklist_items.build(checklist_item_params)
    item.position = template.checklist_items.count + 1
    item.save
    redirect_to checklist_template_path(template)
  end

  def destroy
    item = ChecklistItem.find(params[:id])
    template = item.checklist_template
    item.destroy
    redirect_to checklist_template_path(template)
  end

  private

  def checklist_item_params
    params.require(:checklist_item).permit(:description)
  end
end
