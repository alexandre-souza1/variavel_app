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

  private

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
  end


  def generate_folder_name
    # Limpar caracteres especiais para evitar problemas no SharePoint
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    supplier_name = supplier&.name&.gsub(/[^\w\-]/, '_')&.first(50) || 'unknown_supplier'
    code_clean = code.gsub(/[^\w\-]/, '_')&.first(50)

    "#{code_clean}_#{supplier_name}_#{timestamp}"
  end

end
