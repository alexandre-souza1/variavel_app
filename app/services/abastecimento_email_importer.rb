require "net/imap"
require "mail"
require "tempfile"
require "combine_pdf"

class AbastecimentoEmailImporter
  class Error < StandardError; end

  ALLOWED_TYPES = %w[application/pdf image/jpeg image/png image/tiff].freeze
  DEFAULT_SENDER = "postoparadao1@gmail.com"
  DEFAULT_FOLDER = "INBOX"
  CATEGORY_NAME = "Abastecimento"
  PURCHASER_NAME = "Jovani Beatriz"
  FALLBACK_COST_CENTER = "FOZ ROTA"

  Result = Struct.new(:date, :processed, :skipped, :errors, :invoice_ids, keyword_init: true)

  def self.call(date: Time.zone.yesterday.to_date, progress: nil)
    new(date: date, progress: progress).call
  end

  def initialize(date:, progress: nil)
    @date = date
    @progress = progress
    @setting = InvoiceEmailImportSetting.current
  end

  def call
    result = Result.new(date: @date, processed: 0, skipped: 0, errors: [], invoice_ids: [])
    notify_progress("Conectando ao servidor IMAP...")

    with_imap do |imap|
      uids = search_uids(imap)
      notify_progress("#{uids.size} e-mail(s) encontrado(s). Lendo anexos...")
      pending = fetch_messages(imap, uids).filter_map { |message| prepare_message(message, result) }
      import_messages(pending, result) if pending.any?
    end

    notify_admins(result)
    result
  rescue StandardError => error
    result.errors << error.message
    notify_admins(result)
    raise
  end

  private

  def with_imap
    imap = Net::IMAP.new(
      ENV.fetch("INBOX_ADDRESS", ENV.fetch("SMTP_ADDRESS")),
      port: Integer(ENV.fetch("INBOX_PORT", "993")),
      ssl: ENV.fetch("INBOX_SSL", "true") == "true"
    )
    imap.login(
      ENV.fetch("INBOX_USERNAME", ENV.fetch("SMTP_USERNAME")),
      ENV.fetch("INBOX_PASSWORD", ENV.fetch("SMTP_PASSWORD"))
    )
    imap.select(@setting.imap_folder.presence || DEFAULT_FOLDER)
    yield imap
  ensure
    begin
      imap.logout if imap
    rescue Net::IMAP::Error
      nil
    end
    begin
      imap.disconnect if imap
    rescue Net::IMAP::Error
      nil
    end
  end

  def search_uids(imap)
    imap.uid_search(
      [
        "SINCE", @date.strftime("%d-%b-%Y"),
        "BEFORE", (@date + 1).strftime("%d-%b-%Y"),
        "FROM", @setting.sender_email
      ]
    )
  end

  def fetch_messages(imap, uids)
    uids.filter_map do |uid|
      data = imap.uid_fetch(uid, ["UID", "INTERNALDATE", "BODY.PEEK[]"]).first
      next unless data

      {
        uid: uid,
        received_at: data.attr["INTERNALDATE"],
        raw: data.attr["BODY[]"] || data.attr["BODY.PEEK[]"]
      }
    end
  end

  def prepare_message(message, result)
    mail = Mail.read_from_string(message[:raw])
    sender = mail.from&.first.to_s.downcase
    return unless sender == @setting.sender_email.downcase

    message_id = mail.message_id.presence || "imap-#{message[:uid]}"
    existing = InvoiceEmailImport.find_by(message_id: message_id)
    if existing&.processed?
      result.skipped += 1
      return nil
    end

    record = existing || InvoiceEmailImport.create!(
      message_id: message_id,
      sender: sender,
      subject: mail.subject.to_s,
      received_at: message[:received_at]
    )

    attachments = mail.attachments.filter_map do |attachment|
      next unless ALLOWED_TYPES.include?(attachment.mime_type.to_s.downcase)
      { filename: attachment.filename.to_s, content_type: attachment.mime_type.to_s.downcase, body: attachment.decoded }
    end
    raise Error, "nenhum anexo PDF ou imagem encontrado" if attachments.empty?

    { message: message, record: record, attachments: attachments }
  rescue StandardError => error
    result.errors << "#{mail&.subject || message[:uid]}: #{error.message}"
    record&.update_columns(status: "error", error_message: error.message)
    nil
  end

  def import_messages(pending, result)
    attachments = pending.flat_map { |item| item[:attachments] }
    notify_progress("Consolidando #{attachments.size} anexo(s) em um único PDF...")
    Tempfile.create(["abastecimento-", ".pdf"]) do |merged_file|
      merge_attachments(attachments, merged_file)
      notify_progress("PDF consolidado. Enviando documento ao Textract...")
      extraction = InvoiceTextractService.new(uploaded_pdf(merged_file)).call
      notify_progress("Textract concluído. Criando o lançamento financeiro...")
      invoice = create_invoice!(extraction, merged_file, received_date: pending.map { |item| item[:message][:received_at] }.compact.min)

      pending.each do |item|
        item[:record].update!(status: "processed", invoice: invoice, processed_at: Time.current, error_message: nil)
      end
      result.processed += pending.size
      result.invoice_ids << invoice.id
    end
  rescue StandardError => error
    pending.each { |item| item[:record].update_columns(status: "error", error_message: error.message) }
    result.errors << "Lote de #{pending.size} e-mail(s): #{error.message}"
  end

  def merge_attachments(attachments, output)
    pdf = CombinePDF.new
    temporary_files = []

    attachments.each do |attachment|
      file = Tempfile.new(["invoice-", File.extname(attachment[:filename]).presence || ".bin"])
      file.binmode
      file.write(attachment[:body])
      file.flush
      temporary_files << file

      if attachment[:content_type] == "application/pdf"
        pdf << CombinePDF.load(file.path)
      else
        image = MiniMagick::Image.open(file.path)
        image.format("pdf")
        pdf << CombinePDF.load(image.path)
      end
    end

    pdf.save(output.path)
  ensure
    temporary_files&.each(&:close!)
  end

  def uploaded_pdf(file)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: "notas_abastecimento_#{@date}.pdf",
      type: "application/pdf"
    )
  end

  def create_invoice!(extraction, merged_file, received_date:)
    entries = extraction[:invoices].presence || [extraction]
    category = @setting.budget_category || raise(Error, "categoria padrão da importação não configurada")
    purchaser = @setting.purchaser || raise(Error, "responsável padrão da importação não configurado")
    fallback_center = @setting.fallback_cost_center || raise(Error, "centro de custo fallback não configurado")

    supplier_entry = entries.find { |entry| entry[:supplier_name].to_s.match?(/PARADAO|POSTO/i) } || entries.first
    supplier = supplier_for(supplier_entry)

    date = entries.filter_map { |entry| entry[:date_issued] }.min || received_date&.to_date || @date
    invoice = Invoice.new(
      supplier: supplier,
      purchaser: purchaser,
      budget_category: category,
      date_issued: date,
      due_date: date,
      notes: "Importado automaticamente do e-mail #{@setting.sender_email} em #{@date}."
    )

    entries.each do |entry|
      invoice.invoice_numbers.build(
        number: entry[:invoice_number].presence || raise(Error, "nota sem número"),
        amount: entry[:total].to_d,
        cost_center: CostCenter.find_by(id: entry[:cost_center_id]) || fallback_center
      )
    end

    Invoice.transaction do
      invoice.save!
      merged_file.rewind
      attachment = invoice.documents.attach(
        io: merged_file,
        filename: "notas_abastecimento_#{@date}.pdf",
        content_type: "application/pdf"
      ).last
      attachment.blob.update!(metadata: attachment.blob.metadata.merge(document_type: "nf", source: "email"))
    end

    invoice
  end

  def supplier_for(entry)
    return Supplier.find(entry[:supplier_id]) if entry[:supplier_id].present?

    cnpj = entry[:supplier_cnpj].to_s.gsub(/\D/, "")
    raise Error, "nota sem CNPJ do fornecedor" if cnpj.blank?

    Supplier.find_or_create_by!(cnpj: cnpj) do |supplier|
      supplier.name = entry[:supplier_name].presence || "Fornecedor #{cnpj}"
    end
  end

  def notify_admins(result)
    title = result.errors.empty? ? "Importação de abastecimento finalizada" : "Erro na importação de abastecimento"
    body = "Data: #{result.date.strftime('%d/%m/%Y')}. " \
           "Importados: #{result.processed}. Ignorados: #{result.skipped}."
    body += " Erros: #{result.errors.join(' | ')}" if result.errors.any?

    User.where(role: User.roles[:admin]).find_each do |admin|
      Notification.create!(
        user: admin,
        kind: "abastecimento_email_import",
        title: title,
        body: body,
        action_text: "Abrir invoices",
        action_url: Rails.application.routes.url_helpers.invoices_path
      )
    end
  rescue StandardError => error
    Rails.logger.error("Falha ao notificar admins sobre importação de abastecimento: #{error.message}")
  end

  def notify_progress(message)
    @progress&.call(message)
  end
end
