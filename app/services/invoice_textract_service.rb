require "aws-sdk-textract"
require "aws-sdk-s3"

class InvoiceTextractService
  class Error < StandardError; end

  def initialize(document)
    @document = document
  end

  def call
    validate_document!
    response = pdf? ? analyze_pdf : client.analyze_expense(document: { bytes: document_bytes })
    extract_fields(response)
  rescue Aws::Textract::Errors::ServiceError => e
    Rails.logger.error("Textract error: #{e.message}")
    raise Error, "Não foi possível ler o documento com o Textract."
  end

  private

  def client
    # O Textract não possui endpoint em sa-east-1; o S3 pode continuar nessa região.
    @client ||= Aws::Textract::Client.new(region: ENV.fetch("AWS_TEXTRACT_REGION", "us-east-1"))
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new(region: ENV.fetch("AWS_TEXTRACT_REGION", "us-east-1"))
  end

  def bucket
    ENV.fetch("AWS_TEXTRACT_BUCKET")
  end

  def pdf?
    @document.content_type == "application/pdf"
  end

  def analyze_pdf
    key = "tmp/textract/#{SecureRandom.uuid}.pdf"
    s3_client.put_object(bucket: bucket, key: key, body: document_bytes, content_type: "application/pdf")
    job = client.start_expense_analysis(document_location: { s3_object: { bucket: bucket, name: key } })
    response = wait_for_pdf(job.job_id)
    response
  ensure
    begin
      s3_client.delete_object(bucket: bucket, key: key) if key
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.warn("Não foi possível remover o arquivo temporário do Textract: #{e.message}")
    end
  end

  def wait_for_pdf(job_id)
    30.times do
      response = client.get_expense_analysis(job_id: job_id)
      return response if response.job_status == "SUCCEEDED"
      raise Error, "O Textract não conseguiu processar o PDF." if response.job_status == "FAILED"
      sleep 1
    end
    raise Error, "O Textract demorou mais que o esperado para processar o PDF."
  end

  def validate_document!
    allowed = ["application/pdf", "image/jpeg", "image/png", "image/tiff"]
    raise Error, "Formato não suportado para leitura." unless allowed.include?(@document.content_type)
  end

  def document_bytes
    @document.respond_to?(:download) ? @document.download : @document.read
  end

  def extract_fields(response)
    invoices = response.expense_documents.map { |document| extract_invoice(document) }
      .reject { |invoice| invoice[:invoice_number].blank? && invoice[:total].blank? }
      .uniq { |invoice| invoice[:invoice_number].presence || invoice[:total] }
    first = invoices.first || {}
    {
      supplier_name: first[:supplier_name], supplier_cnpj: first[:supplier_cnpj],
      supplier_id: first[:supplier_id], cost_center_id: first[:cost_center_id],
      invoice_number: first[:invoice_number], date_issued: first[:date_issued],
      total: invoices.sum { |invoice| invoice[:total].to_d }.to_f,
      invoices: invoices
    }
  end

  def extract_invoice(document)
    fields = document.summary_fields
    extra_text = fields.map { |field| field.value_detection&.text }.compact.join(" ")
    extra_text = "#{extra_text} #{line_items(document).map { |item| item[:description] }.compact.join(' ')}"
    # Dados adicionais de NF-e podem aparecer em blocos que não são summary_fields.
    extra_text = "#{extra_text} #{all_text(document)}"
    nfse_service = nfse_service_document?(extra_text)
    supplier = supplier_from_text(extra_text, nfse_service: nfse_service)
    invoice_number = invoice_number_for(fields, extra_text, nfse_service: nfse_service)
    { supplier_name: supplier&.name || value_for(fields, "VENDOR_NAME"), supplier_cnpj: supplier&.cnpj,
      supplier_id: supplier&.id,
      cost_center_id: cost_center_from(extra_text),
      invoice_number: invoice_number,
      date_issued: date_issued_for(fields, extra_text, nfse_service: nfse_service),
      total: total_for(fields, extra_text, nfse_service: nfse_service), items: line_items(document) }
  end

  def nfse_service_document?(text)
    text.to_s.match?(/DANFSe|DOCUMENTO AUXILIAR DA NFS-e/i) &&
      text.to_s.match?(/PRESTADOR\s*\/\s*FORNECEDOR/i)
  end

  def cost_center_from(text)
    normalized = text.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    plate = text[/PLACA\s*:?\s*([A-Z0-9-]{6,})/i, 1]&.upcase
    return CostCenter.where("UPPER(name) LIKE ?", "%#{plate}%").pick(:id) if plate.present?

    # Fallback para OCR que remove o marcador "PLACA:".
    CostCenter.find_each do |center|
      return center.id if normalized.include?(center.name.upcase.gsub(/[^A-Z0-9]/, ""))
    end
    nil
  end

  def all_text(document)
    document.to_h.to_s.scan(/[[:print:]]{3,}/).join(" ")
  end

  def supplier_from_text(text, nfse_service: false)
    search_text = nfse_service ? nfse_provider_section(text) : text
    cnpjs = search_text.scan(/\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}/).map { |cnpj| cnpj.gsub(/\D/, "") }.uniq
    return if cnpjs.empty?

    # Evita uma consulta SQL enorme quando o OCR interpreta códigos e números
    # do documento como possíveis CNPJs.
    Supplier.find_each(batch_size: 500) do |supplier|
      return supplier if cnpjs.include?(supplier.cnpj.to_s.gsub(/\D/, ""))
    end
    nil
  end

  def nfse_provider_section(text)
    text.to_s.match(/PRESTADOR\s*\/\s*FORNECEDOR(.*?)TOMADOR\s*\/\s*ADQUIRENTE/im)&.to_s || text
  end

  def invoice_number_for(fields, text, nfse_service: false)
    if nfse_service
      number = text[/N[ÚU]MERO\s+DA\s+NFS-e\s*:?\s*([0-9]{6,})/i, 1]
      return number if number.present?
    end

    detected = value_for(fields, "INVOICE_RECEIPT_ID")
    # NFS-e: o número correto aparece como 9 dígitos após o ano no código longo.
    # Só considera códigos numéricos longos (ex.: chave/código de validação).
    # Isso evita transformar datas e horários do rodapé em número de NF.
    candidates = text.scan(/\d{20,}/).flat_map { |code| code.scan(/20\d{2}(\d{9})/).flatten }
    candidate = candidates.max_by { |value| value[/^0*/].length }
    if candidate && (detected.blank? || detected.start_with?("20"))
      number = candidate.to_i
      return number.to_s if number.positive?
    end
    detected.to_s.gsub(/\D/, "").sub(/^0+/, "") if detected.present?
  end

  def date_issued_for(fields, text, nfse_service: false)
    detected = value_for(fields, "INVOICE_RECEIPT_DATE")
    if nfse_service
      detected ||= text[/DATA\s+E\s+HORA\s+DA\s+EMISS[AÃ]O\s+DA\s+NFS-e\s*:?\s*(\d{2}\/\d{2}\/\d{4})/i, 1]
      detected ||= text[/DATA\s+DE\s+EMISS[AÃ]O\s*:?\s*(\d{2}\/\d{2}\/\d{4})/i, 1]
    end
    normalize_date(detected)
  end

  def total_for(fields, text, nfse_service: false)
    detected = money_value_for(fields, "TOTAL")
    return detected if detected.present? || !nfse_service

    operation_value = text[/VALOR\s+DA\s+OPERAÇÃO\s*\/\s*SERVIÇO\s*R?\$?\s*([0-9.,]+)/i, 1]
    normalize_money(operation_value)
  end

  def line_items(document)
    document.line_item_groups.flat_map do |group|
      group.line_items.map do |line|
        values = line.line_item_expense_fields
        {
          description: value_for(values, "ITEM"),
          amount: normalize_money(value_for(values, "PRICE"))
        }
      end
    end
  end

  def value_for(fields, type)
    field = fields.find { |item| item.type&.text == type }
    field&.value_detection&.text&.strip
  end

  def money_value_for(fields, type)
    values = fields.select { |item| item.type&.text == type }
                    .map { |item| normalize_money(item.value_detection&.text) }
                    .compact
    values.max
  end

  def normalize_money(value)
    return nil if value.blank?
    value.to_s.gsub(/[^0-9,.-]/, "").then { |v| v.include?(",") ? v.delete(".").tr(",", ".") : v }.to_d.to_f
  end

  def normalize_date(value)
    Date.parse(value.to_s).iso8601 if value.present?
  rescue Date::Error
    nil
  end
end
