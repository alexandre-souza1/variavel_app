# app/pdfs/checklist_pdf.rb
require "prawn"
require "prawn/table"
require "open-uri"

class ChecklistPdf < Prawn::Document
  include Rails.application.routes.url_helpers

  def initialize(checklist)
    super(top_margin: 50)
    @checklist = checklist
    header
    checklist_details
    checklist_items
  end

  def header
    text "Checklist - #{@checklist.checklist_template.name}", size: 18, style: :bold
    move_down 10
    if @checklist.plate.present?
      text "Placa: #{@checklist.plate.placa}", size: 12
    end
    text "Data: #{I18n.l(@checklist.created_at, format: :short)}"
    move_down 20
  end

  def checklist_details
    if @checklist.respond_to?(:user) && @checklist.user.present?
      text "Colaborador: #{@checklist.user.name}"
    end
    move_down 10
  end

def checklist_items
  # Monta as linhas da tabela
  data = [["Descrição", "Status", "Comentário", "Foto"]] # cabeçalho

  @checklist.checklist_responses.each do |resp|
    item = resp.checklist_item
    text_cell = item.description
    status_cell = resp.status.upcase
    comment_cell = resp.comment.presence || "-"

    # Prepara a foto
    if resp.photo.attached?
      begin
        image_url = resp.photo.url
        file = URI.open(image_url)
        # no Prawn, a imagem dentro de uma célula é um hash { image: arquivo, fit: [largura, altura] }
        photo_cell = { image: file, fit: [80, 80], position: :center }
      rescue => e
        photo_cell = "Erro ao carregar foto"
      end
    else
      photo_cell = "" # célula vazia se não houver foto
    end

    data << [text_cell, status_cell, comment_cell, photo_cell]
  end

  # Cria a tabela
  table(data, header: true, column_widths: [200, 60, 150, 130]) do
    row(0).font_style = :bold
    row(0).background_color = "DDDDDD"
    cells.padding = 5
    cells.align = :left
    cells.valign = :center
    cells.borders = [:bottom]
    row(0).borders = [:bottom] # cabeçalho com linha inferior
  end

  move_down 20
end

end
