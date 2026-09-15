require "prawn"
require "prawn/table"

class MeetingMinutePdf < Prawn::Document
  def initialize(meeting)
    super(page_size: "A4", margin: 36)

    @meeting = meeting
    header
    summary_section
    list_section("Decisões", meeting.decisions)
    list_section("Pendências", meeting.pending_items)
    tasks_section
    signatures_section

    number_pages "Página <page> de <total>", at: [bounds.right - 100, 0], size: 7, color: "777777"
  end

  private

  attr_reader :meeting

  def header
    text "ATA DE REUNIÃO", size: 17, style: :bold, color: "173F5F"
    move_down 5
    text meeting.title.to_s, size: 13, style: :bold
    text "Data: #{I18n.l(meeting.meeting_date)} · Action plan: #{meeting.action_plan.name}", size: 9, color: "5F6B76"
    text "Criada por: #{meeting.creator.name}", size: 8, color: "5F6B76"
    move_down 14
  end

  def summary_section
    section_title "Resumo"
    text meeting.summary.presence || "Não informado.", size: 9, leading: 3
    move_down 12
  end

  def list_section(title, items)
    section_title title
    values = Array(items).map(&:to_s).reject(&:blank?)
    if values.empty?
      text "Nenhum item informado.", size: 9, color: "666666"
    else
      values.each { |item| text "- #{item}", size: 9, leading: 3 }
    end
    move_down 10
  end

  def tasks_section
    section_title "Tarefas sugeridas"
    tasks = Array(meeting.tasks_suggestions)
    if tasks.empty?
      text "Nenhuma tarefa foi identificada.", size: 9, color: "666666"
    else
      rows = tasks.map do |task|
        [task["title"].presence || "Tarefa", task["description"].presence || "—", task["due_date"].presence || "—"]
      end
      table([["Tarefa", "Descrição", "Prazo"]] + rows, width: bounds.width,
        cell_style: { padding: [5, 6], size: 8, border_color: "D9E1E8" }) do
        row(0).font_style = :bold
        row(0).background_color = "EDF3F7"
      end
    end
    move_down 14
  end

  def signatures_section
    names = Array(meeting.participants).map(&:to_s).map(&:strip).reject(&:blank?)
    return if names.empty?

    start_new_page if cursor < 170
    section_title "Assinaturas dos participantes"
    rows = names.map { |name| [name, ""] }
    table([["Participante", "Assinatura"]] + rows, width: bounds.width,
      column_widths: [bounds.width * 0.48, bounds.width * 0.52],
      row_colors: ["EDF3F7", "FFFFFF"],
      cell_style: { padding: [4, 6], size: 9, border_color: "D9E1E8" }) do
      row(0).font_style = :bold
      row(1..-1).height = 22
    end
  end

  def section_title(title)
    text title, size: 10, style: :bold, color: "173F5F"
    move_down 5
  end
end
