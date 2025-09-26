class Invoice < ApplicationRecord
  belongs_to :supplier
  has_many_attached :documents, service: :temporary_db
  has_many :invoice_numbers, dependent: :destroy

  accepts_nested_attributes_for :invoice_numbers, allow_destroy: true

  after_commit :upload_documents_to_onedrive, on: :create

  # Categorias possíveis
  enum budget_category: {
    diesel: 0,
    arla: 1,
    pneu: 2,
    alinhamento: 3,
    manutencao_caminhao: 4,
    lavagem: 5
  }

  # Centro de custo (placa ou opções fixas)
  enum cost_center: {
    foz_rota: 0,
    foz_as: 1,
    estoque: 2
    # placas podem ser adicionadas dinamicamente
  }

  # Invoice.rb
  PURCHASERS = ["Jovana", "Maria", "Carlos", "Fernanda", "Lucas"]
  validates :purchaser, inclusion: { in: PURCHASERS }

  validates :code, :date_issued, :due_date, :total, :supplier_id, :purchaser, :budget_category, :cost_center, presence: true
  validates :code, uniqueness: true

  # Método para obter documentos do OneDrive com URLs de download diretas
  def onedrive_documents_with_download
    return [] unless document_urls.present?

    # Usa cache para evitar chamadas repetidas à API
    Rails.cache.fetch("invoice_#{id}_download_urls", expires_in: 1.hour) do
      service = OnedriveService.new

      document_urls.map.with_index do |sharepoint_url, index|
        # Tenta obter URL de download direta
        download_url = service.get_direct_download_url(sharepoint_url) ||
                      service.create_anonymous_download_link(sharepoint_url) ||
                      sharepoint_url

        {
          url: download_url,
          filename: extract_filename_from_url(sharepoint_url) || "documento_#{index + 1}.pdf",
          index: index
        }
      end
    end
  end

  # Método para usar na controller action (sem cache)
  def get_download_url(document_index)
    return nil unless document_urls.present? && document_urls[document_index]

    sharepoint_url = document_urls[document_index]
    service = OnedriveService.new

    service.get_direct_download_url(sharepoint_url) ||
    service.create_anonymous_download_link(sharepoint_url) ||
    sharepoint_url
  end

  private

  def extract_filename_from_url(url)
    begin
      uri = URI.parse(url)
      filename = File.basename(uri.path)
      filename.present? ? CGI.unescape(filename) : nil
    rescue
      nil
    end
  end

  def upload_documents_to_onedrive
    return unless documents.attached?
    return if Rails.env.test?

    service = OnedriveService.new
    folder_name = generate_folder_name

    new_urls = []

    documents.each do |doc|
      begin
        # cria um blob temporário no serviço disk/database
        temp_blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(doc.download),
          filename: doc.filename,
          content_type: doc.content_type,
          service_name: :temporary_db
        )

        # envia para SharePoint
        result = OnedriveService.new.upload_sharepoint_temp(temp_blob.download, doc.filename.to_s, folder_name)

        if result.present?
          url = result.is_a?(Hash) ? result[:web_url] || result["webUrl"] : result
          new_urls << url if url.present?
          Rails.logger.info("✅ Arquivo #{doc.filename} salvo -> #{url}")
        end

        # limpa o blob temporário
        temp_blob.purge

      rescue => e
        Rails.logger.error("Erro ao enviar arquivo #{doc.filename} para SharePoint: #{e.message}")
      end
    end

    # Atualiza o campo no banco (sem sobrescrever os antigos)
    self.update_column(:document_urls, (document_urls + new_urls).uniq)

    # Opcional: Limpar os arquivos do banco de dados após upload para o OneDrive
    clean_local_documents_after_upload
  end

  def clean_local_documents_after_upload
    # Aguarda um pouco para garantir que o upload foi concluído
    DocumentsCleanupJob.set(wait: 5.minutes).perform_later(self.id)
  end

  def generate_folder_name
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    supplier_name = supplier&.name&.gsub(/[^\w\-]/, '_')&.first(50) || 'unknown_supplier'
    code_clean = code.gsub(/[^\w\-]/, '_')&.first(50)

    "#{code_clean}_#{supplier_name}_#{timestamp}"
  end
end
