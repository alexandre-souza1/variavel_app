require 'prawn'
require 'prawn/table'

class InvoiceManagementPdf < Prawn::Document
  include ActionView::Helpers::NumberHelper

  INK = '243447'.freeze
  MUTED = '64748B'.freeze
  BLUE = '3368A0'.freeze
  ORANGE = 'EE7214'.freeze
  BORDER = 'DCE3EA'.freeze

  def initialize(report)
    super(page_size: 'A4', page_layout: :landscape, margin: [68, 28, 36, 28])
    font_families.update('Report' => { normal: Rails.root.join('app/pdfs/fonts/DejaVuSans.ttf'), bold: Rails.root.join('app/pdfs/fonts/DejaVuSans-Bold.ttf') })
    font 'Report'
    font_size 9
    fill_color INK
    @report = report
    overview
    charts
    goal_pages
    category_pages
    invoice_pages
    repeat(:all, dynamic: true) do
      fill_color INK
      label_box 'Financeiro · Relatório gerencial', at: [0, bounds.top + 45], size: 15, style: :bold, height: 22
      label_box "#{report.from.strftime('%d/%m/%Y')} a #{report.to.strftime('%d/%m/%Y')} · Emissão · Gerado em #{Time.current.strftime('%d/%m/%Y %H:%M')}", at: [0, bounds.top + 23], size: 8, color: MUTED, height: 14
      label_box report.scope_label, at: [0, bounds.top + 10], width: bounds.width, size: 7, color: MUTED, height: 12, overflow: :shrink_to_fit
    end
    number_pages 'Relatório financeiro · <page>/<total>', at: [bounds.right - 220, -15], width: 220, size: 7, color: MUTED, align: :right
  end

  private

  def overview
    title 'Visão gerencial do período'
    summary = @report.summary
    report_table([
      ['Gasto lançado', money(summary[:spent]), 'Lançamentos', summary[:count].to_s],
      ['Valor médio por lançamento', money(summary[:ticket]), 'Metas cadastradas', summary[:goals].to_s],
      ["Mês anterior · #{@report.from.prev_month.strftime('%m/%Y')}", money(summary[:previous_spent]), 'Variação sobre o anterior', money(summary[:change])],
      ['Metas excedidas', summary[:exceeded_goals].to_s, 'Gasto sem cobertura de meta', money(summary[:spending_without_goal])]
    ], [0.27, 0.23, 0.27, 0.23], header: false)
    move_down 12
    text 'Base: mês civil e data de emissão, nos setores e centro de custo indicados. Comparação limitada ao mês imediatamente anterior, com os mesmos filtros. Valores lançados não comprovam pagamento. Nenhuma consulta considera todo o histórico do app.', size: 8, color: MUTED
    move_down 8
    text 'Metas: vigentes no mês, ano e setor selecionados, inclusive quando iniciadas em meses anteriores. Uma meta pode agrupar várias categorias; categorias podem participar de mais de uma meta. Os valores das metas e seus excessos não são somados como um único orçamento.', size: 8, color: MUTED
    move_down 14
    title 'Alertas e avaliação técnica'
    report_table([['Ocorrência', 'Evidência e interpretação'], *@report.alerts], [0.25, 0.75])
    move_down 10
    text 'Avaliação calculada pelo app, sem uso de IA. Os pontos de investigação são hipóteses a validar nos documentos; os dados não comprovam a causa de um estouro.', size: 8, color: MUTED
  end

  def charts
    start_new_page
    title 'Gráficos do período'
    top = cursor
    width = (bounds.width - 14) / 2
    @report.charts.each_with_index do |chart, index|
      bounding_box([(index % 2) * (width + 14), top - (index / 2) * 222], width: width, height: 210) do
        chart_card(chart, width)
      end
    end
  end

  def chart_card(chart, width)
    stroke_color BORDER
    line_width 0.6
    stroke { rounded_rectangle([0, 210], width, 210, 7) }
    label_box chart[:title], at: [12, 200], width: width - 24, height: 25, size: 9, style: :bold
    rows = chart[:data]
    if rows.empty?
      label_box 'Sem dados comparáveis neste período.', at: [15, 110], width: width - 30, size: 9, color: MUTED, align: :center
      return
    end
    values = rows.map { |_, value| value.to_f }
    minimum, maximum = [values.min, 0].min, [values.max, chart[:unit] == :percent ? 100 : 1].max
    span = maximum - minimum
    left, plot_width = 122, width - 200
    x_for = ->(value) { left + (value - minimum) / span * plot_width }
    stroke_color BORDER
    [0, (chart[:unit] == :percent ? 100 : maximum)].uniq.each do |value|
      stroke_line [x_for.call(value), 24], [x_for.call(value), 170]
    end
    row_height = 144.0 / rows.size
    rows.each_with_index do |(name, value), index|
      y = 170 - index * row_height
      label_box name, at: [8, y - (row_height - 12) / 2], width: 107, height: 15, size: 7, color: MUTED, align: :right, overflow: :shrink_to_fit, min_font_size: 5
      x, zero = x_for.call(value.to_f), x_for.call(0)
      height = [row_height * 0.65, 28].min
      fill_color value.to_f.negative? || (chart[:unit] == :percent && value.to_f > 100) ? ORANGE : BLUE
      fill_rectangle [[zero, x].min, y - (row_height - height) / 2], [(x - zero).abs, 0.5].max, height
      label_box chart[:unit] == :percent ? percent(value) : money(value), at: [width - 75, y - (row_height - 12) / 2], width: 67, height: 14, size: 7, align: :right, overflow: :shrink_to_fit
    end
    fill_color INK
  end

  def goal_pages
    @report.goals.each do |goal|
      start_new_page
      title "#{goal[:name]} · #{BudgetCategory.sectors.fetch(goal[:sector])}"
      text "#{@report.from.strftime('%m/%Y')} · Categorias: #{goal[:category_names].join(' · ')}", size: 8, color: MUTED
      move_down 10
      report_table([['Aspecto', 'Avaliação e investigação'], *@report.assessment(goal)], [0.24, 0.76])
      move_down 14
      title 'Categorias que compõem a meta'
      category_table(goal[:categories])
      move_down 14
      title 'Fornecedores de maior impacto · até 5'
      if goal[:suppliers].any?
        report_table([['Fornecedor', 'Gasto lançado'], *goal[:suppliers].map { |row| [row[:name], money(row[:spent])] }], [0.76, 0.24])
      else
        text 'Sem lançamentos para esta meta.'
      end
      if goal[:cost_centers].any?
        move_down 14
        title 'Centros de custo · até 5 por valor rateado'
        report_table([['Centro de custo', 'Rateio das notas da meta'], *goal[:cost_centers].map { |row| [row[:name], money(row[:amount])] }], [0.76, 0.24])
      end
      move_down 14
      title 'Documentos para investigação · até 5 por valor'
      invoice_table(goal[:invoices])
    end
  end

  def category_pages
    start_new_page
    title 'Categorias · comparação completa'
    category_table(@report.categories)
    move_down 12
    text 'A comparação anterior usa as mesmas categorias. Sem registros anteriores, a variação fica indisponível. Participação no gasto não equivale a desvio de uma meta individual por categoria.', size: 8, color: MUTED
  end

  def category_table(rows)
    if rows.empty?
      text 'Sem lançamentos nas categorias deste recorte.'
      return
    end
    report_table([['Categoria / setor', 'Gasto', '% do período', 'Mês anterior', 'Variação R$', 'Cobertura'], *rows.map do |row|
      ["#{row[:name]}\n#{BudgetCategory.sectors.fetch(row[:sector])}", money(row[:spent]), percent(row[:share]),
        money(row[:previous]), money(row[:change]), row[:has_goal] ? 'Com meta' : 'Sem meta']
    end], [0.30, 0.15, 0.10, 0.15, 0.15, 0.15])
  end

  def invoice_pages
    start_new_page
    title 'Maiores lançamentos do período · até 20'
    invoice_table(@report.largest_invoices)
    move_down 12
    text "Ranking de #{@report.largest_invoices.size} dos #{@report.summary[:count]} lançamentos do mês. Os totais e as avaliações consideram todos os registros autorizados do período, sem depender do tamanho dos rankings.", size: 8, color: MUTED
  end

  def invoice_table(rows)
    if rows.empty?
      text 'Sem lançamentos neste recorte.'
      return
    end
    report_table([['Documento / emissão', 'Fornecedor / categoria', 'Valor', 'Observações cadastradas (até 500 caracteres)'], *rows.map do |row|
      ["#{row[:code].presence || row[:id]}\n#{row[:date].strftime('%d/%m/%Y')}", "#{row[:supplier]}\n#{row[:category]}", money(row[:total]), row[:notes].presence || 'Sem observação']
    end], [0.16, 0.32, 0.15, 0.37])
  end

  def title(content)
    start_new_page if cursor < 90
    text content, size: 12, style: :bold, color: INK
    move_down 9
  end

  def label_box(content, **options)
    color = options.delete(:color) || INK
    formatted_text_box([{ text: content.to_s, color: color }], options)
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
    value.nil? ? 'Sem base' : number_to_currency(value, unit: 'R$ ', delimiter: '.', separator: ',')
  end

  def percent(value)
    value.nil? ? 'Sem base' : "#{number_with_precision(value, precision: 2, separator: ',')}%"
  end
end
