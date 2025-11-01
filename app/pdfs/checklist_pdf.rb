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
    truck_photos_section # 🔹 nova seção com as 6 fotos
    checklist_items
    signature_section
  end

  private

  def header
    text "Checklist - #{@checklist.checklist_template.name}", size: 18, style: :bold
    move_down 10

    if @checklist.plate.present?
      text "Placa selecionada: #{@checklist.plate.placa}", size: 12
    elsif @checklist.placa_manual.present?
      text "Placa informada: #{@checklist.placa_manual}", size: 12
    end

    text "Data: #{I18n.l(@checklist.created_at, format: :short)}", size: 12
    move_down 15
  end

  def checklist_details
    lines = []

    lines << ["Modelo do veículo", @checklist.vehicle_model] if @checklist.vehicle_model.present?
    lines << ["Quilometragem", "#{@checklist.kilometer} km"] if @checklist.kilometer.present?

    if @checklist.gas_state.present?
      gas_label = {
        "full" => "Cheio",
        "three_quarters" => "3/4",
        "half" => "1/2",
        "quarter" => "1/4",
        "empty" => "Vazio"
      }[@checklist.gas_state] || @checklist.gas_state
      lines << ["Nível de combustível", gas_label]
    end

    lines << ["Responsável", @checklist.responsavel] if @checklist.responsavel.present?
    lines << ["Origem", @checklist.origin] if @checklist.origin.present?

    return if lines.empty?

    table(lines, cell_style: { borders: [], padding: [3, 5] }, column_widths: [160, 300]) do
      cells.size = 12
      column(0).font_style = :bold
    end

    move_down 20
  end

def truck_photos_section
  photos = {
    "Frente" => @checklist.photo_front,
    "Lado esquerdo (cavalo)" => @checklist.photo_left_truck,
    "Lado esquerdo (implemento)" => @checklist.photo_left_trailer,
    "Traseira" => @checklist.photo_back,
    "Lado direito (implemento)" => @checklist.photo_right_trailer,
    "Lado direito (cavalo)" => @checklist.photo_right_truck
  }

  attached_photos = photos.select { |_label, photo| photo.attached? }
  return if attached_photos.empty?

  text "Fotos do Caminhão", size: 14, style: :bold
  move_down 10

  attached_photos.each_slice(3) do |row_photos|
    # Cria arrays separados para imagens e legendas
    image_cells = []
    label_cells = []

    row_photos.each do |label, photo|
      begin
        file = URI.open(photo.url)
        image_cells << { image: file, fit: [160, 160], position: :center }
        label_cells << { content: label, align: :center, size: 10 }
      rescue
        image_cells << { content: "Erro ao carregar\nfoto", align: :center, valign: :center, size: 8 }
        label_cells << { content: label, align: :center, size: 10 }
      end
    end

    # Preenche células vazias se a linha não estiver completa
    while image_cells.length < 3
      image_cells << { content: "" }
      label_cells << { content: "" }
    end

    # Calcula a largura das colunas antes de entrar no bloco da tabela
    column_width = bounds.width / 3

    # Cria tabela com duas linhas: uma para imagens, outra para legendas
    table([image_cells, label_cells],
          width: bounds.width,
          cell_style: {
            borders: [],
            padding: [2, 5, 2, 5],
            align: :center
          }) do |table|
      # Define alturas para as linhas
      table.row(0).height = 100 # Altura para as imagens
      table.row(1).height = 15  # Altura para as legendas

      # Define larguras iguais para as colunas
      table.columns(0..2).width = column_width
    end

    move_down 10
  end

  move_down 20
end

  def checklist_items
    data = [["Descrição", "Status", "Comentário", "Foto"]]

    @checklist.checklist_responses.each do |resp|
      item = resp.checklist_item
      text_cell = item.description
      status_cell = resp.status.upcase
      comment_cell = resp.comment.presence || "-"

      if resp.photo.attached?
        begin
          file = URI.open(resp.photo.url)
          photo_cell = { image: file, fit: [80, 80], position: :center }
        rescue
          photo_cell = "Erro ao carregar foto"
        end
      else
        photo_cell = ""
      end

      data << [text_cell, status_cell, comment_cell, photo_cell]
    end

    table(data, header: true, column_widths: [180, 60, 150, 130]) do
      row(0).font_style = :bold
      row(0).background_color = "DDDDDD"
      cells.padding = 5
      cells.valign = :center
      row(0).borders = [:bottom]
    end

    move_down 40
  end

  def signature_section
    move_down 60

    data = [
      [
        { content: "______________________________\nResponsável pela assinatura", align: :center },
        { content: "______________________________\nData", align: :center }
      ]
    ]

    table(data, cell_style: { borders: [], padding: [10, 10], size: 10 },
          column_widths: [250, 250], position: :center)
  end
end
