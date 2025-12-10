class Invoice < ApplicationRecord
  belongs_to :supplier
  belongs_to :purchaser, class_name: 'User', foreign_key: 'purchaser_id'
  has_many_attached :documents, service: :temporary_db
  has_many :invoice_numbers, dependent: :destroy
  belongs_to :budget_category

  before_validation :ensure_code_for_abastecimento, on: :create

  accepts_nested_attributes_for :invoice_numbers, allow_destroy: true

  after_commit :upload_documents_to_onedrive, on: :create

  validates :purchaser_id, presence: true
  validates :date_issued, :due_date, :total, :supplier_id, :budget_category_id, presence: true
  validates :code, uniqueness: { allow_blank: true }

  # Validação customizada para o code
  validate :code_required_unless_abastecimento

  # Método para obter a lista de purchasers ativos
  def self.available_purchasers
    User.all.order(:name).pluck(:name, :id)
  end

  # Método para compatibilidade com views existentes
  def purchaser_name
    purchaser&.name
  end

  # Método para obter documentos do OneDrive com URLs de download diretas
  def onedrive_documents_with_download
    return [] unless document_urls.present?

    Rails.cache.fetch("invoice_#{id}_download_urls", expires_in: 1.hour) do
      service = OnedriveService.new

      document_urls.map.with_index do |sharepoint_url, index|
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

  def code_required_unless_abastecimento
    # Se NÃO for abastecimento E code estiver em branco, adiciona erro
    if budget_category&.name&.downcase != 'abastecimento' && code.blank?
      errors.add(:code, "é obrigatório para esta categoria")
    end
  end

  def ensure_code_for_abastecimento
    # Se for abastecimento e não tiver código, gera um automático
    if budget_category&.name&.downcase == 'abastecimento' && code.blank?
      self.code = "ABAST-#{Date.today.strftime('%Y%m%d')}-#{SecureRandom.alphanumeric(6).upcase}"
    end
  end

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
        temp_blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(doc.download),
          filename: doc.filename,
          content_type: doc.content_type,
          service_name: :temporary_db
        )

        result = OnedriveService.new.upload_sharepoint_temp(temp_blob.download, doc.filename.to_s, folder_name)

        if result.present?
          url = result.is_a?(Hash) ? result[:web_url] || result["webUrl"] : result
          new_urls << url if url.present?
          Rails.logger.info("✅ Arquivo #{doc.filename} salvo -> #{url}")
        end

        temp_blob.purge

      rescue => e
        Rails.logger.error("Erro ao enviar arquivo #{doc.filename} para SharePoint: #{e.message}")
      end
    end

    self.update_column(:document_urls, (document_urls + new_urls).uniq)
    clean_local_documents_after_upload
  end

  def clean_local_documents_after_upload
    DocumentsCleanupJob.set(wait: 5.minutes).perform_later(self.id)
  end

  def generate_folder_name
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    supplier_name = supplier&.name&.gsub(/[^\w\-]/, '_')&.first(50) || 'unknown_supplier'
    code_clean = code.gsub(/[^\w\-]/, '_')&.first(50)

    "#{code_clean}_#{supplier_name}_#{timestamp}"
  end
end
