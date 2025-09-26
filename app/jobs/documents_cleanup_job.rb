class DocumentsCleanupJob < ApplicationJob
  queue_as :default

  def perform(invoice_id)
    invoice = Invoice.find_by(id: invoice_id)
    return unless invoice

    # Verifica se há URLs do OneDrive salvas
    if invoice.document_urls.present? && invoice.document_urls.any?
      # Remove os documentos do banco local
      invoice.documents.purge
      Rails.logger.info("Documentos locais removidos para invoice #{invoice.id}")
    end
  end
end
