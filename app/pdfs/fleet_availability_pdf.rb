require "prawn"
require "prawn/table"

class FleetAvailabilityPdf < Prawn::Document
  STATUS_TITLES = {
    available: "Disponibilidade",
    special_route: "Rotas especiais",
    unavailable: "Indisponíveis",
    exchange: "Disponíveis para Troca"
  }.freeze

  def initialize(fleet_availability)
    super(page_size: "A4", page_layout: :landscape, margin: 20)

    @fleet_availability = fleet_availability
    @items = fleet_availability
             .fleet_availability_items
             .includes(:plate)
             .ordered
    @standard_plate_by_position =
      FleetAvailability
      .dimensioning_period_for(fleet_availability.date)
      &.standard_plate_by_position || {}

    header
    dashboard_section
    main_section
    special_routes_section
  end

  private

  attr_reader :fleet_availability, :items

  def header
    text "Disponibilidade da Frota",
         size: 16,
         style: :bold

    move_down 4

    text "Data: #{I18n.l(fleet_availability.date)}",
         size: 9

    text "Gerado em: #{I18n.l(Time.current, format: :short)}",
         size: 7,
         color: "666666"

    move_down 8
  end

  def dashboard_section
    top = cursor

    summary_width = bounds.width * 0.72
    profile_width = bounds.width - summary_width - 10

    bounding_box([0, top], width: summary_width) do
      summary
    end

    bounding_box([summary_width + 10, top], width: profile_width) do
      profile_summary
    end

    move_cursor_to(top - 38)
  end

  def main_section
    top = cursor
    left_width = bounds.width * 0.68
    right_width = bounds.width - left_width - 10

    # Caixa da esquerda (disponibilidade)
    bounding_box([0, top], width: left_width) do
      available_section
    end
    left_bottom = cursor  # posição y após desenhar a caixa esquerda

    # Caixa da direita (Disponíveis para Troca + indisponíveis)
    bounding_box([left_width + 10, top], width: right_width) do
      deposit_section
      move_down 8
      unavailable_section
    end
    right_bottom = cursor  # posição y após desenhar a caixa direita

    # Ponto mais baixo entre as duas caixas
    lowest_y = [left_bottom, right_bottom].min

    # Move o cursor 12 pontos abaixo desse ponto
    move_cursor_to(lowest_y - 12)
  end

  def summary
    data = [
      ["Dimensionamento", fleet_availability.agreed_quantity.to_s],
      ["Disponíveis", fleet_availability.available_count.to_s],
      ["Rotas especiais", items.select(&:special_route?).size.to_s],
      ["Indisponíveis", fleet_availability.unavailable_count.to_s],
      ["Disponíveis para Troca", fleet_availability.deposit_count.to_s],
      ["Cobertura", "#{fleet_availability.coverage_percentage}%"]
    ]

    table(data.each_slice(3).map(&:flatten),
          width: bounds.width,
          cell_style: {
            size: 7,
            padding: [3, 5],
            borders: [:top, :bottom, :left, :right],
            border_color: "DDDDDD"
          }) do
      columns([0, 2, 4]).font_style = :bold
      columns([0, 2, 4]).background_color = "F4F6F8"
    end

    move_down 8
  end

  def available_section
    available_items = items.select(&:available?)
    highlighted_rows = []
    rows =
      fleet_availability.agreed_quantity.to_i.times.map do |position|
        item = available_items[position]
        plate = item&.plate
        standard_plate = standard_plate_at(position)

        if standard_plate&.id != plate&.id
          highlighted_rows << position
        end

        changed = standard_plate&.id != plate&.id ? "Sim" : "Não"

        [
          standard_plate&.placa || "-",
          standard_plate&.perfil.presence || "-",
          changed,
          plate&.placa || "-",
          plate&.perfil.presence || "-",
          item&.observation.presence || "-"
        ]
      end

    # Larguras fixas para as 5 primeiras colunas (ordem atual)
    fixed_widths = [100, 70, 40, 100, 70]   # soma = 245
    obs_width = bounds.width - fixed_widths.sum  # o resto para Observação

    col_widths = fixed_widths + [obs_width]

    table_section(
      STATUS_TITLES[:available],
      ["Placa padrão", "Perfil padrão", "Trocada?", "Placa atualizada", "Perfil atual", "Observação"],
      rows,
      highlighted_rows: highlighted_rows,
      column_widths: col_widths
    )
  end

  def profile_summary
    profile_counts =
      items.select(&:available?)
           .map { |item| item.plate.perfil.to_s.upcase }
           .tally

    data = [
      ["VUC", profile_counts["VUC"].to_i],
      ["TOCO", profile_counts["TOCO"].to_i],
      ["TRUCK", profile_counts["TRUCK"].to_i],
      ["BITRUCK", profile_counts["BITRUCK"].to_i]
    ]

    table([data.flatten],
          width: bounds.width,
          cell_style: {
            size: 7,
            padding: [3, 5],
            border_color: "DDDDDD"
          }) do
      columns([0, 2, 4, 6]).font_style = :bold
      columns([0, 2, 4, 6]).background_color = "F4F6F8"
    end

    move_down 8
  end

  def special_routes_section
    rows =
      items.select(&:special_route?).map do |item|
        plate = item.plate

        [
          item.special_route_label,
          plate.placa,
          item.observation.presence || "-"
        ]
      end

    table_section(
      STATUS_TITLES[:special_route],
      ["Rota", "Placa", "Observação"],
      rows
    )
  end

  def unavailable_section
    rows =
      items.select(&:unavailable?).map do |item|
        plate = item.plate

        [
          plate.placa,
          item.reason_label,
          item.observation.presence || "-"
        ]
      end

    # Larguras fixas para as 5 primeiras colunas (ordem atual)
    fixed_widths = [50, 50]   # soma = 245
    obs_width = bounds.width - fixed_widths.sum  # o resto para Observação

    col_widths = fixed_widths + [obs_width]

    table_section(
      STATUS_TITLES[:unavailable],
      ["Placa", "Defeito", "Observação"],
      rows, column_widths: col_widths
    )
  end

  def deposit_section
    rows =
      items.select(&:exchange?).map do |item|
        plate = item.plate

        [
          plate.placa,
          item.observation.presence || "-"
        ]
      end

      # Larguras fixas para as 5 primeiras colunas (ordem atual)
      fixed_widths = [50]
      obs_width = bounds.width - fixed_widths.sum  # o resto para Observação

      col_widths = fixed_widths + [obs_width]

    table_section(
      STATUS_TITLES[:exchange],
      ["Placa", "Observação"],
      rows, column_widths: col_widths
    )
  end

  def table_section(title, headers, rows, highlighted_rows: [], column_widths: nil)
    text title, size: 10, style: :bold
    move_down 4

    if rows.empty?
      text "Nenhum item.", size: 7, color: "666666"
      move_down 6
      return
    end

    # Se não foram definidas larguras, calcula proporcionalmente
    unless column_widths
      total_width = bounds.width
      obs_width   = total_width * 0.30          # 45% para observação
      other_width = (total_width - obs_width) / (headers.size - 1) # resto dividido igualmente
      column_widths = Array.new(headers.size - 1, other_width) + [obs_width]
    end

    table([headers] + rows,
          header: true,
          width: bounds.width,
          cell_style: { size: 7, padding: [3, 4], border_color: "DDDDDD" }) do
      row(0).font_style = :bold
      row(0).background_color = "E9ECEF"
      highlighted_rows.each do |index|
        row(index + 1).background_color = "FFF3CD"
      end
      cells.valign = :center

      column_widths.each_with_index do |w, i|
        columns(i).width = w
      end
    end

    move_down 8
  end

  def standard_plate_for(position)
    standard_plate_at(position)&.placa || "-"
  end

  def standard_plate_at(position)
    @standard_plate_by_position[position]&.plate
  end
end
