class WmsTasksController < ApplicationController
  def index
    @tasks = WmsTask.includes(:operator).order(created_at: :desc).page(params[:page])

    # Corrigindo o cálculo das datas
    dates = @tasks.pluck(:started_at).compact
    @data_inicio_WMS = dates.min
    @data_fim_WMS = dates.max
    @dias_periodo_WMS = (@data_fim_WMS - @data_inicio_WMS).to_i if @data_inicio_WMS && @data_fim_WMS
  end

  def new_import
    # Renderiza o formulário de importação
  end

  def import
    if params[:file].nil?
      redirect_to new_import_wms_tasks_path, alert: 'Selecione um arquivo!'
      return
    end

    begin
      result = WmsTask.import(params[:file])

      if result[:imported] > 0
        notice = "Importação concluída! #{result[:imported]}/#{result[:total_rows]} tarefas importadas."
        notice += " Operadores não encontrados: #{result[:skipped_operators].join(', ')}" if result[:skipped_operators].any?
        flash[:notice] = notice
      else
        alert = "Nenhuma tarefa importada. Verifique os nomes dos operadores."
        alert += " Operadores não encontrados: #{result[:skipped_operators].join(', ')}" if result[:skipped_operators].any?
        flash[:alert] = alert
      end

      if result[:failed_rows].any?
        flash[:error_details] = "Erros em #{result[:failed_rows].size} linhas."
        Rails.logger.error "Falhas na importação: #{result[:failed_rows]}"
      end

    rescue => e
      flash[:alert] = "Erro durante a importação: #{e.message}"
      Rails.logger.error "Erro na importação: #{e.backtrace.join("\n")}"
    end

    redirect_to wms_tasks_path
  end
end
