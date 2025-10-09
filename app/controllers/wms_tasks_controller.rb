class WmsTasksController < ApplicationController
  def index
    all_tasks = WmsTask.includes(:operator).order(created_at: :desc)

    pagination = helpers.paginate_records(all_tasks, params, per_page: 15)

    @tasks = pagination[:records]
    @current_page = pagination[:current_page]
    @total_pages = pagination[:total_pages]
    @total_tasks = all_tasks.count

    dates = all_tasks.pluck(:started_at).compact
    @data_inicio_WMS = dates.min
    @data_fim_WMS = dates.max
    @dias_periodo_WMS = (@data_fim_WMS - @data_inicio_WMS).to_i if @data_inicio_WMS && @data_fim_WMS
  end

  def new_import
    # Renderiza o formulário de importação
  end

def import
  if params[:file].present?
    begin
      # Lê o arquivo como binário primeiro
      file_content = params[:file].read.force_encoding('BINARY')

      # Remove BOM se existir e converte para UTF-8
      file_content = remove_bom_and_convert_to_utf8(file_content)

      # Salva o arquivo temporariamente
      filename = "import_#{Time.now.to_i}_#{SecureRandom.hex(8)}.csv"
      file_path = Rails.root.join('tmp', filename).to_s

      File.write(file_path, file_content, mode: 'wb')

      # Enfileira o job
      WmsTaskImportJob.perform_later(file_path, current_user.id)

      # ✅ SOLUÇÃO 1: Fica na mesma página em vez de redirect
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            # Atualiza a mensagem de status
            turbo_stream.update("import-status",
              "<div class='alert alert-info alert-dismissible fade show'>
                <strong>📤 Importação Iniciada!</strong><br>
                <small>O arquivo está sendo processado em segundo plano.</small>
                <small class='d-block mt-1'>📊 Você será notificado quando terminar.</small>
                <button type='button' class='btn-close' data-bs-dismiss='alert'></button>
              </div>"
            ),
            # Limpa o campo de arquivo
            turbo_stream.update("file-input",
              "<input type='file' name='file' accept='.csv' class='form-control' required>"
            )
          ]
        end
        format.html {
          # Fallback para HTML normal
          redirect_to new_import_wms_tasks_path, notice: 'Importação iniciada...'
        }
      end

    rescue => e
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("import-status",
            "<div class='alert alert-danger alert-dismissible fade show'>
              <strong>❌ Erro:</strong> #{e.message}
              <button type='button' class='btn-close' data-bs-dismiss='alert'></button>
            </div>"
          )
        end
        format.html {
          redirect_to new_import_wms_tasks_path, alert: "Erro: #{e.message}"
        }
      end
    end
  else
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("import-status",
          "<div class='alert alert-warning alert-dismissible fade show'>
            <strong>⚠️ Atenção:</strong> Por favor, selecione um arquivo.
            <button type='button' class='btn-close' data-bs-dismiss='alert'></button>
          </div>"
        )
      end
      format.html {
        redirect_to new_import_wms_tasks_path, alert: 'Por favor, selecione um arquivo.'
      }
    end
  end
end

  def delete_all
    count = WmsTask.count
    WmsTask.destroy_all
    flash[:notice] = "#{count} tarefas foram deletadas com sucesso."
    redirect_to wms_tasks_path
  end

  private

  def remove_bom_and_convert_to_utf8(content)
    # Remove Byte Order Mark (BOM) se existir
    bom_bytes = "\xEF\xBB\xBF".force_encoding('BINARY')
    if content.start_with?(bom_bytes)
      content = content.byteslice(3..-1) || ''
    end

    # Tenta detectar o encoding e converter para UTF-8
    detected_encoding = detect_encoding(content)

    if detected_encoding
      content.force_encoding(detected_encoding)
      content.encode!('UTF-8', invalid: :replace, undef: :replace, replace: '')
    else
      # Fallback: força UTF-8 e remove caracteres inválidos
      content.force_encoding('UTF-8')
      content.scrub!('')
    end

    content
  end

  def detect_encoding(content)
    # Tenta UTF-8 primeiro
    utf8_content = content.dup.force_encoding('UTF-8')
    return 'UTF-8' if utf8_content.valid_encoding?

    # Tenta ISO-8859-1 (common em sistemas Windows/Brasil)
    iso_content = content.dup.force_encoding('ISO-8859-1')
    return 'ISO-8859-1' if iso_content.valid_encoding?

    # Tenta Windows-1252
    windows_content = content.dup.force_encoding('Windows-1252')
    return 'Windows-1252' if windows_content.valid_encoding?

    # Não conseguiu detectar
    nil
  end
end
