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
    super(page_size: "A4", margin: 28)

    @fleet_availability = fleet_availability
    @items = fleet_availability
             .fleet_availability_items
             .includes(:plate)
             .ordered

    header
    summary
    available_section
    special_routes_section
    unavailable_section
    deposit_section
  end

  private

  attr_reader :fleet_availability, :items

  def header
    text "Disponibilidade da Frota",
         size: 20,
         style: :bold

    move_down 6

    text "Data: #{I18n.l(fleet_availability.date)}",
         size: 11

    text "Gerado em: #{I18n.l(Time.current, format: :short)}",
         size: 9,
         color: "666666"

    move_down 14
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
            size: 9,
            padding: [6, 7],
            borders: [:top, :bottom, :left, :right],
            border_color: "DDDDDD"
          }) do
      columns([0, 2, 4]).font_style = :bold
      columns([0, 2, 4]).background_color = "F4F6F8"
    end

    move_down 14
  end

  def available_section
    rows =
      items.select(&:available?).map.with_index(1) do |item, index|
        plate = item.plate

        [
          index.to_s,
          plate.placa,
          plate.tipo.presence || "-",
          plate.perfil.presence || "-"
        ]
      end

    table_section(
      STATUS_TITLES[:available],
      ["Linha", "Placa", "Tipo", "Perfil"],
      rows
    )
  end

  def special_routes_section
    rows =
      items.select(&:special_route?).map do |item|
        plate = item.plate

        [
          item.special_route_label,
          plate.placa,
          plate.tipo.presence || "-",
          plate.perfil.presence || "-"
        ]
      end

    table_section(
      STATUS_TITLES[:special_route],
      ["Rota", "Placa", "Tipo", "Perfil"],
      rows
    )
  end

  def unavailable_section
    rows =
      items.select(&:unavailable?).map do |item|
        plate = item.plate

        [
          plate.placa,
          plate.tipo.presence || "-",
          plate.perfil.presence || "-",
          item.reason_label,
          item.observation.presence || "-"
        ]
      end

    table_section(
      STATUS_TITLES[:unavailable],
      ["Placa", "Tipo", "Perfil", "Defeito", "Observação"],
      rows
    )
  end

  def deposit_section
    rows =
      items.select(&:exchange?).map do |item|
        plate = item.plate

        [
          plate.placa,
          plate.tipo.presence || "-",
          plate.perfil.presence || "-"
        ]
      end

    table_section(
      STATUS_TITLES[:exchange],
      ["Placa", "Tipo", "Perfil"],
      rows
    )
  end

  def table_section(title, headers, rows)
    start_new_page if cursor < 120

    text title,
         size: 13,
         style: :bold

    move_down 6

    if rows.empty?
      text "Nenhum item.",
           size: 9,
           color: "666666"
      move_down 12
      return
    end

    table([headers] + rows,
          header: true,
          width: bounds.width,
          cell_style: {
            size: 8,
            padding: [5, 5],
            border_color: "DDDDDD"
          }) do
      row(0).font_style = :bold
      row(0).background_color = "E9ECEF"
      cells.valign = :center
    end

    move_down 14
  end
end
