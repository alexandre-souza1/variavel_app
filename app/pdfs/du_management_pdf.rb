require 'prawn'
require 'prawn/table'

class DuManagementPdf < Prawn::Document
  include ActionView::Helpers::NumberHelper

  INK = '243447'.freeze
  MUTED = '64748B'.freeze
  BLUE = '3368A0'.freeze
  ORANGE = 'EE7214'.freeze
  BORDER = 'DCE3EA'.freeze

  def initialize(report)
    super(page_size: 'A4', page_layout: :landscape, margin: [62, 28, 36, 28])
    font_families.update('Report' => { normal: Rails.root.join('app/pdfs/fonts/DejaVuSans.ttf'), bold: Rails.root.join('app/pdfs/fonts/DejaVuSans-Bold.ttf') })
    font 'Report'
    font_size 9
    fill_color INK
    @report = report
    overview
    chart_pages
    remuneration_pages
    comparison_pages
    repeat(:all, dynamic: true) do
      fill_color INK
      label_box 'DU · Relatório gerencial de variável', at: [0, bounds.top + 35], size: 15, style: :bold, height: 22
      label_box "#{report.from.strftime('%d/%m/%Y')} a #{report.to.strftime('%d/%m/%Y')} · Gerado em #{Time.current.strftime('%d/%m/%Y %H:%M')}", at: [0, bounds.top + 14], size: 8, color: MUTED, height: 14
    end
    number_pages 'Relatório DU · <page>/<total>', at: [bounds.right - 180, -15], width: 180, size: 7, color: MUTED, align: :right
  end

  private

  def overview
    section_title('Visão gerencial do período')
    summary = @report.devolution.general
    driver_total = @report.drivers.sum { |row| row[:valor_total].to_d }
    helper_total = @report.helpers.sum { |row| row[:valor_total].to_d }
    rows = [
      ['Mapas operacionais', @report.maps.size.to_s, 'Variável total', money(@report.total_variable)],
      ['Variável · Motoristas', money(driver_total), 'Variável · Ajudantes', money(helper_total)],
      ['PDVs previstos válidos', summary[:total].to_i.to_s, 'PDVs devolvidos', summary[:returned].to_i.to_s],
      ['Devolução geral', summary[:percentage] ? percent(summary[:percentage] * 100) : 'Sem dados', 'Fechamentos usados', (@report.drivers + @report.helpers).select { |row| row[:source] == 'closing' }.map { |row| row[:person_key] }.uniq.size.to_s]
    ]
    report_table(rows, [0.27, 0.23, 0.27, 0.23], header: false)
    move_down 10
    text 'Remunerações: último fechamento salvo do ciclo, quando disponível; demais valores são calculados pelos mapas do período. Devolução: fontes operacionais atuais. Os fechamentos salvos não são alterados.', size: 8, color: MUTED
    move_down 10
    text "Referência histórica: #{@report.averages.from.strftime('%m/%Y')} a #{@report.averages.to.strftime('%m/%Y')}. Soma da variável por pessoa/mês ÷ registros computados, com a última revisão de cada fechamento DU. Motorista e van da mesma pessoa são somados uma vez no mês. Valores zerados com mapas entram na média; meses sem dados não viram zero.", size: 8, color: MUTED
    move_down 14
    section_title('Alertas e pontos de atenção')
    report_table([['Ocorrência', 'Evidência'], *@report.alerts], [0.27, 0.73])
  end

  def chart_pages
    @report.charts.each_slice(4) do |charts|
      start_new_page
      section_title('Gráficos do período')
      top = cursor
      width = (bounds.width - 14) / 2
      charts.each_with_index do |chart, index|
        bounding_box([(index % 2) * (width + 14), top - (index / 2) * 224], width: width, height: 210) do
          chart_card(chart, width, 210)
        end
      end
    end
  end

  def chart_card(chart, width, height)
    stroke_color BORDER
    line_width 0.6
    stroke { rounded_rectangle([0, height], width, height, 7) }
    label_box chart[:title], at: [12, height - 10], width: width - 24, height: 22, size: 10, style: :bold, color: INK
    if chart[:data].empty?
      label_box 'Sem dados nesta faixa ou período.', at: [15, 110], width: width - 30, size: 9, color: MUTED, align: :center
      return
    end
    case chart[:kind]
    when :bars then bars(chart, width)
    when :line then line_chart(chart, width)
    when :donut then donut(chart, width)
    end
  end

  def bars(chart, width)
    rows = chart[:data]
    values = rows.map { |_, value| value.to_f }
    minimum = [values.min, 0].min
    maximum = [values.max, 0].max
    span = maximum - minimum
    span = 1 if span.zero?
    plot_left = 115
    plot_width = width - 185
    x_for = ->(value) { plot_left + (value - minimum) / span * plot_width }
    zero = x_for.call(0)
    stroke_color BORDER
    5.times do |index|
      x = plot_left + plot_width * index / 4.0
      stroke_line [x, 26], [x, 170]
    end
    stroke_color MUTED
    stroke_line [zero, 26], [zero, 170]
    row_height = 144.0 / rows.size
    rows.each_with_index do |(name, value), index|
      y = 170 - index * row_height
      label_box name.to_s, at: [10, y - (row_height - 12) / 2], width: 98, height: 13, size: 7.5, overflow: :shrink_to_fit, min_font_size: 5.5, color: MUTED, align: :right
      x = x_for.call(value.to_f)
      bar_height = [row_height * 0.65, 28].min
      fill_color value.to_f.negative? ? ORANGE : BLUE
      fill_rectangle [[zero, x].min, y - (row_height - bar_height) / 2], [(x - zero).abs, 0.5].max, bar_height
      label_box value_label(value, chart[:unit]), at: [width - 65, y - (row_height - 12) / 2], width: 57, height: 13, size: 7, overflow: :shrink_to_fit, color: INK, align: :right
    end
    label_box value_label(minimum, chart[:unit]), at: [plot_left - 8, 19], width: 85, height: 14, size: 6.5, color: MUTED
    label_box value_label(maximum, chart[:unit]), at: [plot_left + plot_width - 65, 19], width: 75, height: 14, size: 6.5, color: MUTED, align: :right
    fill_color INK
  end

  def line_chart(chart, width)
    rows = chart[:data]
    maximum = [rows.map { |_, value| value.to_f }.max, 1].max
    left, bottom, plot_height = 45, 37, 125
    plot_width = width - 65
    stroke_color BORDER
    4.times do |index|
      y = bottom + plot_height * index / 3.0
      stroke_line [left, y], [left + plot_width, y]
      label_box value_label(maximum * index / 3.0, chart[:unit]), at: [5, y + 5], width: 35, height: 12, size: 6.5, color: MUTED, align: :right
    end
    points = rows.each_with_index.map do |(_, value), index|
      [left + plot_width * index / [rows.size - 1, 1].max, bottom + value.to_f / maximum * plot_height]
    end
    stroke_color BLUE
    line_width 1.2
    stroke do
      move_to points.first
      points.drop(1).each { |point| line_to point }
    end
    fill_color BLUE
    points.each { |point| fill_circle point, 2 }
    [0, rows.size / 2, rows.size - 1].uniq.each do |index|
      x = points[index][0]
      label_box rows[index][0].to_s, at: [[x - 35, left].max.clamp(left, width - 80), 27], width: 75, height: 14, size: 6.5, color: MUTED
    end
    fill_color INK
  end

  def donut(chart, width)
    total = chart[:data].sum { |_, value| value.to_f }
    center = [width * 0.34, 104]
    angle = Math::PI / 2
    chart[:data].each_with_index do |(_, value), index|
      portion = value.to_f / total * 2 * Math::PI
      steps = [(portion * 20).ceil, 1].max
      points = (0..steps).map do |step|
        theta = angle + portion * step / steps
        [center[0] + 60 * Math.cos(theta), center[1] + 60 * Math.sin(theta)]
      end
      fill_color index.zero? ? BLUE : ORANGE
      fill { polygon(center, *points) }
      angle += portion
    end
    fill_color 'FFFFFF'
    fill_circle center, 38
    returned = @report.devolution.general[:percentage]
    label_box percent(returned * 100), at: [center[0] - 38, center[1] + 10], width: 76, height: 22, size: 15, align: :center, style: :bold, color: INK
    chart[:data].each_with_index do |(name, value), index|
      fill_color index.zero? ? BLUE : ORANGE
      fill_rectangle [width * 0.58, 133 - index * 30], 8, 8
      label_box "#{name}: #{value.to_i}", at: [width * 0.58 + 15, 136 - index * 30], width: width * 0.38, size: 8, color: INK
    end
    fill_color INK
  end

  def remuneration_pages
    { 'Motoristas e van' => @report.drivers, 'Ajudantes' => @report.helpers }.each do |label, entries|
      start_new_page
      section_title("Remunerações · #{label}")
      text "Total do grupo: #{money(entries.sum { |row| row[:valor_total].to_d })}", size: 10, style: :bold
      move_down 8
      if entries.empty?
        text 'Sem remunerações no período.'
        next
      end
      rows = entries.map do |row|
        bonus = row[:bonus_devolucao].to_d
        ["#{row[:nome]}\nMatrícula: #{row[:matricula]}", row[:cargo].presence || (label == 'Ajudantes' ? 'ajudante' : 'motorista'),
          row[:mapas].to_s, money(row[:valor_total].to_d - bonus), money(bonus), money(row[:valor_total]),
          row[:percentual_devolucao].nil? ? '—' : percent(row[:percentual_devolucao] * 100), row[:source] == 'closing' ? 'Fechamento' : 'Calculado']
      end
      report_table([['Colaborador', 'Cargo', 'Mapas', 'Base', 'Bônus', 'Variável', 'Dev.%', 'Origem'], *rows], [0.29, 0.09, 0.05, 0.12, 0.10, 0.14, 0.08, 0.13])
    end
  end

  def comparison_pages
    DuVariableAverageReport::PROFILES.each do |profile, label|
      start_new_page
      section_title("Comparação completa · #{label}")
      summary = @report.averages.summary(profile)
      text "Média histórica mensal: #{summary[:average].nil? ? 'Sem histórico' : money(summary[:average])} · #{summary[:months]}/12 meses · #{summary[:observations]} registros", size: 9
      move_down 8
      entries = @report.averages.entries(profile)
      if entries.empty?
        text 'Sem colaboradores com mapas no período.'
        next
      end
      rows = entries.map do |person|
        delta = person[:difference]
        ["#{person[:name]}\nMatrícula: #{person[:registration]}", person[:maps].to_s, money(person[:value]),
          summary[:average].nil? ? 'Sem histórico' : money(summary[:average]), delta.nil? ? '—' : money(delta),
          { below: 'Abaixo da média', above: 'Acima da média', equal: 'Na média', unavailable: 'Sem histórico' }.fetch(person[:position])]
      end
      report_table([['Colaborador', 'Mapas', 'Variável', 'Referência mensal', 'Diferença', 'Comparação'], *rows], [0.34, 0.06, 0.14, 0.14, 0.14, 0.18])
    end
  end

  def label_box(content, **options)
    color = options.delete(:color) || INK
    formatted_text_box([{ text: content.to_s, color: color }], options)
  end

  def section_title(title)
    text title, size: 12, style: :bold, color: INK
    move_down 9
  end

  def report_table(rows, widths, header: true)
    table(rows, header: header, column_widths: widths.map { |part| part * bounds.width },
      cell_style: { size: 8, padding: 6, border_color: BORDER, valign: :center }, row_colors: ['FFFFFF', 'F5F7FA']) do
      if header
        row(0).font_style = :bold
        row(0).background_color = 'E7EDF3'
      end
    end
  end

  def money(value)
    number_to_currency(value, unit: 'R$ ', delimiter: '.', separator: ',')
  end

  def percent(value)
    "#{format('%.2f', value).tr('.', ',')}%"
  end

  def value_label(value, unit)
    case unit
    when :currency then money(value)
    when :percent then percent(value)
    else number_with_delimiter(value.round, delimiter: '.')
    end
  end
end
