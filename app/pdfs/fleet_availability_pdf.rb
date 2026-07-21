require "prawn"
require "prawn/table"

class FleetAvailabilityPdf < Prawn::Document
  STATUS_TITLES = {
    available: "Disponibilidade",
    special_route: "Rotas especiais",
    unavailable: "Indisponíveis",
    exchange: "Depósito"
  }.freeze

  def initialize(fleet_availability)
    super(page_size: "A4", margin: 20)

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
    summary
    profile_summary
    available_section
    special_routes_section
    unavailable_section
    deposit_section
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

  def summary
    data = [
      ["Dimensionamento", fleet_availability.agreed_quantity.to_s],
      ["Disponíveis", fleet_availability.available_count.to_s],
      ["Rotas especiais", items.select(&:special_route?).size.to_s],
      ["Indisponíveis", fleet_availability.unavailable_count.to_s],
      ["Depósito", fleet_availability.deposit_count.to_s],
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

        [
          standard_plate&.placa || "-",
          standard_plate&.perfil.presence || "-",
          plate&.placa || "-",
          plate&.perfil.presence || "-"
        ]
      end

    table_section(
      STATUS_TITLES[:available],
      ["Placa padrão", "Perfil padrão", "Placa atualizada", "Perfil atual"],
      rows,
      highlighted_rows: highlighted_rows
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
          plate.placa
        ]
      end

    table_section(
      STATUS_TITLES[:special_route],
      ["Rota", "Placa"],
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

    table_section(
      STATUS_TITLES[:unavailable],
      ["Placa", "Defeito", "Observação"],
      rows
    )
  end

  def deposit_section
    rows =
      items.select(&:exchange?).map do |item|
        plate = item.plate

        [
          plate.placa
        ]
      end

    table_section(
      STATUS_TITLES[:exchange],
      ["Placa"],
      rows
    )
  end

  def table_section(title, headers, rows, highlighted_rows: [])
    start_new_page if cursor < 80

    text title,
         size: 10,
         style: :bold

    move_down 4

    if rows.empty?
      text "Nenhum item.",
           size: 7,
           color: "666666"
      move_down 6
      return
    end

    table([headers] + rows,
          header: true,
          width: bounds.width,
          cell_style: {
            size: 7,
            padding: [3, 4],
            border_color: "DDDDDD"
          }) do
      row(0).font_style = :bold
      row(0).background_color = "E9ECEF"
      highlighted_rows.each do |index|
        row(index + 1).background_color = "FFF3CD"
      end
      cells.valign = :center
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
