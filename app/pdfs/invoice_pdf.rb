require "prawn"
require "prawn/table"

class InvoicePdf < Prawn::Document
  include ActionView::Helpers::NumberHelper

  def initialize(invoice)
    super(page_size: "A4", margin: 32)

    @invoice = invoice
    @supplier = invoice.supplier
    @invoice_numbers = invoice.invoice_numbers.includes(:cost_center)
    header
    summary
    details
    invoice_numbers_section
    notes
    signatures
    number_pages "Página <page> de <total>", at: [bounds.right - 100, 0], size: 7, color: "777777"
  end

  private

  attr_reader :invoice, :supplier, :invoice_numbers, :other_invoices

  def header
    bounding_box([0, cursor], width: bounds.width, height: 64) do
      stroke_color "173F5F"
      fill_color "173F5F"
      fill_rectangle [0, bounds.top], bounds.width, bounds.height
      fill_color "FFFFFF"
      draw_text "COMPROVANTE DE LANÇAMENTO", at: [14, bounds.top - 22], size: 15, style: :bold
      draw_text "Documento para conferência do registro financeiro", at: [14, bounds.top - 41], size: 8
      text_box invoice.code.presence || "Lançamento ##{invoice.id}", at: [bounds.right - 150, bounds.top - 17], width: 136, height: 20, align: :right, size: 10, style: :bold
    end
    # O cabeçalho usa branco sobre azul; o restante do comprovante deve usar
    # texto escuro para manter a leitura das tabelas e dos detalhes.
    fill_color "1F2937"
    move_down 18
  end

  def summary
    due_status = invoice.due_date.present? && invoice.due_date < Date.current ? "Vencido" : "A vencer"

    table([
      ["VALOR DO LANÇAMENTO", "VENCIMENTO", "NOTAS FISCAIS", "DOCUMENTOS"],
      [currency(invoice.total), invoice.due_date ? I18n.l(invoice.due_date) : "—", invoice_numbers.size.to_s, invoice.documents.count.to_s]
    ], width: bounds.width, cell_style: { padding: [7, 8], size: 8, border_color: "D9E1E8" }) do
      row(0).font_style = :bold
      row(0).text_color = "5F6B76"
      row(0).background_color = "EDF3F7"
      row(1).font_style = :bold
      row(1).size = 11
      row(1).columns(0).text_color = "198754"
      row(1).columns(1).text_color = due_status == "Vencido" ? "B42318" : "198754"
    end
    move_down 15
  end

  def details
    section_title "Identificação do lançamento"
    rows = [
      ["Código do lançamento", invoice.code.presence || "Não informado", "ID do registro", invoice.id.to_s],
      ["Fornecedor", supplier.name, "CNPJ", supplier.cnpj.to_s],
      ["Categoria", invoice.budget_category&.name&.titleize || "Não informada", "Setor", invoice.budget_category&.sector.presence || "—"],
      ["Responsável", invoice.purchaser&.name || "Não informado", "Situação", due_status],
      ["Data de emissão", invoice.date_issued ? I18n.l(invoice.date_issued) : "—", "Vencimento", invoice.due_date ? I18n.l(invoice.due_date) : "—"]
    ]
    table(rows, width: bounds.width, cell_style: { padding: [5, 7], size: 8, border_color: "E1E5E8" }) do
      columns([0, 2]).font_style = :bold
      columns([0, 2]).text_color = "5F6B76"
      columns([1, 3]).font_style = :bold
    end
    move_down 14
  end

  def invoice_numbers_section
    section_title "Composição do lançamento"
    rows = invoice_numbers.map do |item|
      [item.number.to_s, item.cost_center&.name || "Sem centro de custo", currency(item.amount)]
    end
    rows = [["Nenhum número cadastrado", "—", "—"]] if rows.empty?
    table([["Número da NF", "Centro de custo", "Valor"]] + rows,
          width: bounds.width,
          cell_style: { padding: [5, 7], size: 8, border_color: "E1E5E8" }) do
      row(0).font_style = :bold
      row(0).background_color = "EDF3F7"
      columns(2).align = :right
    end
    move_down 14
  end

  def notes
    section_title "Documentos e observações"
    documents = invoice.documents.map { |document| document.filename.to_s }
    text "Documentos: #{documents.any? ? documents.join(", ") : "Nenhum documento anexado"}", size: 8
    if invoice.notes.present?
      move_down 5
      text "Observações:", size: 8, style: :bold
      text invoice.notes.to_s, size: 8
    end
  end

  def signatures
    move_down 20
    stroke_color "B8C2CC"
    stroke_horizontal_line 0, bounds.width
    move_down 18
    table([["Responsável pelo lançamento", "Conferência"]], width: bounds.width, cell_style: { borders: [], padding: 0, size: 8, text_color: "555555" })
    move_down 22
    table([["________________________________________", "________________________________________"]], width: bounds.width, cell_style: { borders: [], padding: 0, size: 8, text_color: "555555" })
    move_down 12
    text "Comprovante gerado em #{I18n.l(Time.current, format: :short)} · As informações refletem o cadastro do lançamento no sistema.", size: 7, color: "777777"
  end

  def section_title(title)
    text title, size: 10, style: :bold, color: "173F5F"
    move_down 5
  end

  def currency(value)
    number_to_currency(value, unit: "R$ ", separator: ",", delimiter: ".")
  end

  def due_status
    invoice.due_date.present? && invoice.due_date < Date.current ? "Vencido" : "A vencer"
  end

end
