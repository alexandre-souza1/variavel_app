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

    if @checklist.vehicle_model.present?
      lines << ["Modelo do veículo", @checklist.vehicle_model]
    end

    if @checklist.kilometer.present?
      lines << ["Quilometragem", "#{@checklist.kilometer} km"]
    end

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

    if @checklist.responsavel.present?
      lines << ["Responsável", @checklist.responsavel]
    end

    return if lines.empty?

    table(lines, cell_style: { borders: [], padding: [3, 5] }, column_widths: [160, 300]) do
      cells.size = 12
      column(0).font_style = :bold
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
  end
end
