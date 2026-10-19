require "net/imap"
require "mail"
require "tempfile"
require "combine_pdf"
require "nokogiri"

class AbastecimentoEmailImporter
  class Error < StandardError; end

  ALLOWED_TYPES = %w[application/pdf image/jpeg image/png image/tiff].freeze
  DEFAULT_SENDER = "postoparadao1@gmail.com"
  DEFAULT_FOLDER = "INBOX"
  CATEGORY_NAME = "Abastecimento"
  PURCHASER_NAME = "Jovani Beatriz"
  FALLBACK_COST_CENTER = "FOZ ROTA"

  Result = Struct.new(:date, :processed, :skipped, :errors, :invoice_ids, keyword_init: true) do
    def title
      return "Importação de abastecimento finalizada" if errors.empty?
      return "Importação de abastecimento concluída com pendências" if processed.positive?

      "Erro na importação de abastecimento"
    end

    def summary
      body = "Data: #{date.strftime('%d/%m/%Y')}. Importados: #{processed}. Ignorados: #{skipped}."
      body += " Erros: #{errors.join(' | ')}" if errors.any?
      body
    end
  end

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
      pending = fetch_messages(imap, uids, result).filter_map { |message| prepare_message(message, result) }
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

  def fetch_messages(imap, uids, result)
    uids.filter_map do |uid|
      data = imap.uid_fetch(uid, ["UID", "INTERNALDATE", "BODY.PEEK[]"]).first
      raise Error, "e-mail não encontrado no servidor" unless data

      {
        uid: uid,
        received_at: data.attr["INTERNALDATE"],
        raw: data.attr["BODY[]"] || data.attr["BODY.PEEK[]"]
      }
    rescue StandardError => error
      result.errors << "E-mail UID #{uid}: #{error.message}"
      nil
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
      received_at: message[:received_at],
      status: "pending"
    )

    if cancellation_message?(mail)
      record.update!(status: "ignored", error_message: nil)
      result.skipped += 1
      return nil
    end

    attachments = mail.attachments.filter_map do |attachment|
      next unless ALLOWED_TYPES.include?(attachment.mime_type.to_s.downcase)
      { filename: attachment.filename.to_s, content_type: attachment.mime_type.to_s.downcase, body: attachment.decoded }
    end
    xml_attachments = mail.attachments.filter_map do |attachment|
      next unless File.extname(attachment.filename.to_s).downcase == ".xml"

      { filename: attachment.filename.to_s, body: attachment.decoded }
    end
    raise Error, "nenhum anexo PDF, imagem ou XML encontrado" if attachments.empty? && xml_attachments.empty?

    { message: message, record: record, attachments: attachments, xml_attachments: xml_attachments }
  rescue StandardError => error
    result.errors << "#{message_label(message, mail&.subject)}: #{error.message}"
    record&.update_columns(status: "error", error_message: error.message)
    nil
  end

  def import_messages(pending, result)
    valid = pending.filter_map do |item|
      notify_progress("Lendo #{message_label(item[:message], item[:record].subject)}...")
      Tempfile.create(["abastecimento-email-", ".pdf"]) do |file|
        merge_attachments(item[:attachments], file) if item[:attachments].any?
        extraction = if item[:xml_attachments].any?
                       { invoices: item[:xml_attachments].map { |attachment| extract_xml(attachment) } }
                     else
                       InvoiceTextractService.new(uploaded_pdf(file)).call
                     end
        invoice = build_invoice(extraction, received_date: item[:message][:received_at])
        raise ActiveRecord::RecordInvalid, invoice unless invoice.valid?

        item.merge(extraction: extraction)
      end
    rescue StandardError => error
      record_import_error(item, result, error)
      nil
    end
    return if valid.empty?

    save_messages(valid, result)
  end

  def save_messages(pending, result)
    attachments = pending.flat_map { |item| item[:attachments] }
    xml_attachments = pending.flat_map { |item| item[:xml_attachments] }
    notify_progress("Consolidando #{attachments.size} anexo(s) em um único PDF...")
    Tempfile.create(["abastecimento-", ".pdf"]) do |merged_file|
      merge_attachments(attachments, merged_file) if attachments.any?
      extraction = { invoices: pending.flat_map { |item| invoice_entries(item[:extraction]) } }
      notify_progress("Criando o lançamento financeiro com #{pending.size} e-mail(s) válido(s)...")
      invoice = Invoice.transaction do
        created = create_invoice!(
          extraction, attachments.any? ? merged_file : nil,
          received_date: pending.map { |item| item[:message][:received_at] }.compact.min,
          xml_attachments: xml_attachments
        )
        pending.each do |item|
          item[:record].update!(status: "processed", invoice: created, processed_at: Time.current, error_message: nil)
        end
        created
      end
      result.processed += pending.size
      result.invoice_ids << invoice.id
    end
  rescue StandardError => error
    pending.each { |item| record_import_error(item, result, error) }
  end

  def message_label(message, subject)
    "E-mail UID #{message[:uid]} (#{subject.presence || 'sem assunto'})"
  end

  def record_import_error(item, result, error)
    filenames = (item[:attachments] + item[:xml_attachments]).map { |attachment| attachment[:filename] }.join(", ")
    result.errors << "#{message_label(item[:message], item[:record].subject)}; anexos: #{filenames}: #{error.message}"
    item[:record].update_columns(status: "error", error_message: error.message)
  end

  def extract_xml(attachment)
    InvoiceNfeXmlService.new(attachment[:body]).call
  rescue InvoiceNfeXmlService::Error => error
    raise Error, "#{attachment[:filename]}: #{error.message}"
  end

  def cancellation_message?(mail)
    return true if mail.subject.to_s.match?(/\b(?:cancelamento|cancelad[ao]s?)\b/i)

    mail.attachments.any? do |attachment|
      next false unless File.extname(attachment.filename.to_s).downcase == ".xml"

      xml = Nokogiri::XML(attachment.decoded) { |config| config.strict.nonet }
      xml.xpath("//*[local-name()='tpEvento']").any? { |node| node.text.strip == "110111" }
    rescue Nokogiri::XML::SyntaxError
      false
    end
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

  def invoice_entries(extraction)
    extraction[:invoices].presence || [extraction]
  end

  def build_invoice(extraction, received_date:)
    entries = invoice_entries(extraction)
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

    entries.each_with_index do |entry, index|
      invoice.invoice_numbers.build(
        number: entry[:invoice_number].presence || raise(Error, "nota sem número (documento #{index + 1})"),
        amount: entry[:total].to_d,
        cost_center: CostCenter.find_by(id: entry[:cost_center_id]) || fallback_center
      )
    end

    invoice
  end

  def create_invoice!(extraction, merged_file, received_date:, xml_attachments: [])
    invoice = build_invoice(extraction, received_date: received_date)
    Invoice.transaction do
      invoice.save!
      documents = []
      if merged_file
        merged_file.rewind
        documents << {
          io: merged_file,
          filename: "notas_abastecimento_#{@date}.pdf",
          content_type: "application/pdf",
          metadata: { document_type: "nf", source: "email" }
        }
      end
      xml_attachments.each do |attachment|
        documents << {
          io: StringIO.new(attachment[:body]), filename: attachment[:filename],
          content_type: "application/xml", metadata: { document_type: "nf", source: "email" }
        }
      end
      invoice.documents.attach(documents)
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
    User.where(role: User.roles[:admin]).find_each do |admin|
      Notification.create!(
        user: admin,
        kind: "abastecimento_email_import",
        title: result.title,
        body: result.summary,
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
