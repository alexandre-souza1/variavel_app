class TaskImportsController < ApplicationController
  def new
    # Só renderiza a tela de upload
  end

  def create
    if params[:file].blank?
      redirect_to new_task_import_path, alert: "Selecione um arquivo."
      return
    end

    TaskImportService.new(params[:file], current_user).call

    redirect_to action_plans_path, notice: "Importação realizada com sucesso! 🚀"
    
  end
end