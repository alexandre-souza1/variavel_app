require "test_helper"
require "minitest/mock"

class AbastecimentoEmailImporterTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 10, 17)
    @category = BudgetCategory.create!(name: "Abastecimento", sector: :frota)
    users(:one).update!(sector: :fleet)
    InvoiceEmailImportSetting.current.update!(
      purchaser: users(:one), budget_category: @category, fallback_cost_center: cost_centers(:one)
    )
    @supplier = Supplier.create!(name: "PARADAO AUTO POSTO", cnpj: "07388800000170")
    @importer = AbastecimentoEmailImporter.new(date: @date)
    @pdf = CombinePDF.new
    @pdf << CombinePDF.create_page
  end

  test "imports valid notes together when another email has no invoice number" do
    messages = [email_message(1), email_message(2), email_message(3)]
    result = nil
    assert_difference "Invoice.count", 1 do
      result = import(messages, [extraction("110210"), extraction(nil), extraction("110214")])
    end

    assert_equal 2, result.processed
    assert_equal 1, result.errors.size
    assert_match "UID 2 (NF-e 2)", result.errors.first
    assert_match "nota-2.pdf", result.errors.first
    assert_match "nota sem número", result.errors.first
    invoice = Invoice.find(result.invoice_ids.sole)
    assert_equal %w[110210 110214], invoice.invoice_numbers.order(:number).pluck(:number)
    assert_equal 200.to_d, invoice.total
    assert_equal 2, CombinePDF.parse(invoice.documents.sole.download).pages.size
    assert_equal "error", record(2).status
    assert_equal invoice, record(1).invoice
    assert_equal invoice, record(3).invoice
    assert_match "concluída com pendências", result.title
    assert_match "Importados: 2. Ignorados: 0.", result.summary
  end

  test "ignores cancellation subjects and XML events while importing remaining notes" do
    cancellation = email_message(2, subject: "Cancelamento da NF-e 110211", pdf: false)
    xml_event = email_message(3, subject: "Evento NF-e", pdf: false, xml: <<~XML)
      <procEventoNFe xmlns="http://www.portalfiscal.inf.br/nfe">
        <evento><infEvento><tpEvento>110111</tpEvento></infEvento></evento>
      </procEventoNFe>
    XML
    result = import([cancellation, xml_event, email_message(1)], [extraction("110210")])

    assert_equal 1, result.processed
    assert_equal 2, result.skipped
    assert_empty result.errors
    assert_equal "ignored", record(2).status
    assert_equal "ignored", record(3).status
    assert_nil record(2).invoice
  end

  test "reads XML without Textract and preserves the grouped PDF and original XMLs" do
    result = import([email_message(1, xml: invoice_xml("110210")), email_message(2, xml: invoice_xml("110212"))], [])

    assert_equal 2, result.processed
    assert_empty result.errors
    invoice = Invoice.find(result.invoice_ids.sole)
    assert_equal %w[110210 110212], invoice.invoice_numbers.order(:number).pluck(:number)
    assert_equal @supplier, invoice.supplier
    assert_equal @date, invoice.date_issued
    assert_equal 1788.66.to_d, invoice.total
    assert_equal 3, invoice.documents.count
    pdf = invoice.documents.find { |document| document.content_type == "application/pdf" }
    assert_equal 2, CombinePDF.parse(pdf.download).pages.size
    invoice.documents.reject { |document| document == pdf }.each do |document|
      assert_includes document.download, "<nfeProc"
      assert_equal "nf", document.metadata["document_type"]
    end
  end

  test "accepts XML without a PDF and resolves cost center from additional invoice information" do
    center = CostCenter.create!(name: "RDZ9A66", sector: "FROTA")
    result = import([email_message(1, pdf: false, xml: invoice_xml("110210"))], [])

    assert_equal 1, result.processed
    assert_empty result.errors
    invoice = Invoice.find(result.invoice_ids.sole)
    assert_equal center, invoice.invoice_numbers.sole.cost_center
    assert_equal "application/xml", invoice.documents.sole.content_type
    assert_includes invoice.documents.sole.download, "<nfeProc"
  end

  test "reports malformed XML without paid OCR fallback and imports the other notes" do
    result = import([
      email_message(1, xml: "<nfeProc>"),
      email_message(2, xml: invoice_xml("")),
      email_message(3, xml: invoice_xml("110214"))
    ], [])

    assert_equal 1, result.processed
    assert_equal 2, result.errors.size
    assert_match "evento.xml: XML malformado", result.errors.first
    assert_match "nota sem número no XML", result.errors.last
    assert_equal "processed", record(3).status
    assert_equal 2, Invoice.find(result.invoice_ids.sole).documents.count
  end

  test "retries only failed emails without duplicating previously imported notes" do
    messages = [email_message(1), email_message(2)]
    import(messages, [extraction("110210"), extraction(nil)])

    assert_difference "Invoice.count", 1 do
      result = import(messages, [extraction("110212")])
      assert_equal 1, result.processed
      assert_equal 1, result.skipped
      assert_empty result.errors
    end
    assert_equal 1, InvoiceNumber.where(number: "110210").count
    assert_equal "processed", record(2).status
    assert_nil record(2).error_message
  end

  test "continues after an unreadable PDF, OCR failure, validation error or missing attachment" do
    messages = [email_message(1, body: "invalid PDF"), email_message(2), email_message(3), email_message(4, pdf: false), email_message(5)]
    result = import(messages, [RuntimeError.new("Textract indisponível"), extraction("110214", total: -10), extraction("110216")])

    assert_equal 1, result.processed
    assert_equal 4, result.errors.size
    (1..4).each { |uid| assert_equal "error", record(uid).status }
    assert_equal "processed", record(5).status
    assert_match "Textract indisponível", result.errors.join
    assert_match "nenhum anexo", result.errors.join
  end

  test "reports all failures without creating an empty financial entry" do
    assert_no_difference "Invoice.count" do
      result = import([email_message(1), email_message(2)], [extraction(nil), extraction(nil)])
      assert_equal 0, result.processed
      assert_equal 2, result.errors.size
      assert_empty result.invoice_ids
    end
  end

  test "rolls back the grouped invoice if an email status cannot be saved" do
    pending = [email_message(1), email_message(2)].map { |value| @importer.send(:prepare_message, value, empty_result) }
    pending.last[:record].stub(:update!, ->(**) { raise "Falha ao salvar status" }) do
      assert_no_difference "Invoice.count" do
        result = empty_result
        with_extractions([extraction("110210"), extraction("110212")]) do
          @importer.send(:import_messages, pending, result)
        end
        assert_equal 0, result.processed
        assert_equal 2, result.errors.size
        assert_empty result.invoice_ids
      end
    end
    assert_nil record(1).invoice_id
    assert_nil record(2).invoice_id
  end

  test "continues fetching when an individual email cannot be read" do
    imap = Object.new
    def imap.uid_fetch(uid, _attributes)
      raise "Falha na leitura" if uid == 1

      [Struct.new(:attr).new({ "BODY[]" => "mail", "INTERNALDATE" => Time.current })]
    end
    result = empty_result
    messages = @importer.send(:fetch_messages, imap, [1, 2], result)

    assert_equal [2], messages.pluck(:uid)
    assert_match "UID 1: Falha na leitura", result.errors.sole
  end

  private

  def empty_result
    AbastecimentoEmailImporter::Result.new(date: @date, processed: 0, skipped: 0, errors: [], invoice_ids: [])
  end

  def record(uid)
    InvoiceEmailImport.find_by!(message_id: "fuel-#{uid}@example.test")
  end

  def email_message(uid, subject: "NF-e #{uid}", pdf: true, body: @pdf.to_pdf, xml: nil)
    mail = Mail.new
    mail.from = InvoiceEmailImportSetting.current.sender_email
    mail.subject = subject
    mail.message_id = "fuel-#{uid}@example.test"
    mail.body = "Nota fiscal"
    mail.attachments["nota-#{uid}.pdf"] = { mime_type: "application/pdf", content: body } if pdf
    mail.attachments["evento.xml"] = { mime_type: "text/xml", content: xml } if xml
    { uid: uid, received_at: Time.zone.local(2026, 10, 17, 12), raw: mail.to_s }
  end

  def extraction(number, total: 100)
    { invoices: [{ invoice_number: number, supplier_id: @supplier.id, total: total, date_issued: @date.iso8601 }] }
  end

  def invoice_xml(number)
    <<~XML
      <nfeProc xmlns="http://www.portalfiscal.inf.br/nfe">
        <NFe><infNFe>
          <ide><nNF>#{number}</nNF><dhEmi>2026-10-17T18:42:38-03:00</dhEmi></ide>
          <emit><CNPJ>07388800000170</CNPJ><xNome>PARADAO AUTO POSTO</xNome></emit>
          <dest><CNPJ>13631347001407</CNPJ><xNome>LOG20</xNome></dest>
          <total><ICMSTot><vNF>894.33</vNF></ICMSTot></total>
          <infAdic><infCpl>Placa: RDZ9A66 KM: 73950</infCpl></infAdic>
        </infNFe></NFe>
      </nfeProc>
    XML
  end

  def with_extractions(extractions)
    remaining = extractions.dup
    factory = lambda do |_document|
      raise "Extração inesperada" if remaining.empty?

      response = remaining.shift
      service = Object.new
      service.define_singleton_method(:call) do
        raise response if response.is_a?(Exception)

        response
      end
      service
    end
    InvoiceTextractService.stub(:new, factory) { yield }
    assert_empty remaining
  end

  def import(messages, extractions)
    imap = Object.new
    imap.define_singleton_method(:uid_search) { |_criteria| messages.pluck(:uid) }
    imap.define_singleton_method(:uid_fetch) do |uid, _attributes|
      value = messages.find { |item| item[:uid] == uid }
      [Struct.new(:attr).new({ "BODY[]" => value[:raw], "INTERNALDATE" => value[:received_at] })]
    end
    result = nil
    @importer.stub(:with_imap, ->(&block) { block.call(imap) }) do
      @importer.stub(:notify_admins, nil) do
        with_extractions(extractions) { result = @importer.call }
      end
    end
    result
  end
end
