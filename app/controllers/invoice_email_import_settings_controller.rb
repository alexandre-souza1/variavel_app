class InvoiceEmailImportSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin_or_finance!

  def edit
    @setting = InvoiceEmailImportSetting.current
    load_options
  end

  def update
    @setting = InvoiceEmailImportSetting.current

    if @setting.update(setting_params)
      redirect_to edit_invoice_email_import_setting_path,
                  notice: "Configuração da importação por e-mail salva com sucesso."
    else
      load_options
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def setting_params
    params.require(:invoice_email_import_setting).permit(
      :sender_email, :imap_folder, :schedule_time, :purchaser_id,
      :budget_category_id, :fallback_cost_center_id
    )
  end

  def load_options
    @purchasers = User.active.order(:name)
    @budget_categories = BudgetCategory.order(:name)
    @cost_centers = CostCenter.order(:name)
  end
end
