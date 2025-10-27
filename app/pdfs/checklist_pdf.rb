require 'prawn'
require 'prawn/table'

class ChecklistPdf < Prawn::Document
  def initialize(checklist)
    super()
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
    text "Colaborador: #{@checklist.user.name}" if @checklist.respond_to?(:user) && @checklist.user.present?
    move_down 10
  end

  def checklist_items
    table_data = [["Item", "Status", "Comentário"]]
    @checklist.checklist_responses.each do |resp|
      item = resp.checklist_item
      table_data << [
        item.description,
        resp.status.upcase,
        resp.comment.presence || "-"
      ]
    end

    table(table_data, header: true, width: bounds.width) do
      row(0).font_style = :bold
      columns(1..2).align = :center
      self.row_colors = ["F0F0F0", "FFFFFF"]
    end
  end
end
