require 'prawn'
require 'prawn/table'

class PcdPdf < Prawn::Document
  def initialize(board)
    super(page_size: 'A4', page_layout: :landscape, margin: 16)
    font_families.update('PCD' => { normal: Rails.root.join('app/pdfs/fonts/DejaVuSans.ttf'), bold: Rails.root.join('app/pdfs/fonts/DejaVuSans-Bold.ttf') })
    font 'PCD'
    @board = board
    groups = board.cars.select { |c| c['scheduled'] }.group_by { |c| [c['room'], c['departure_time']] }
    groups.sort_by { |(room, time), _| [Pcd::Board::ROOMS.keys.index(room), time] }.each_with_index do |((room, time), cars), index|
      start_new_page unless index.zero?
      text safe('PCD SALAS'), size: 16, style: :bold
      text safe("#{I18n.l(board.date)} · #{Pcd::Board::ROOMS.fetch(room).first} · #{time}"), size: 10
      move_down 10
      header = ['Data', 'Placa', 'Mapa', 'Oper.', 'Id', 'Motorista', 'Ajudantes', 'Ent.', 'Cidades +Entregas', 'Região +Entregas', 'KM', 'Tempo', 'Caixas', 'Ocup. cx %', 'Peso', 'Ocup. peso %']
      rows = cars.flat_map do |car|
        maps = car['maps'].presence || [{}]
        driver = board.member(car['driver'])
        helpers = (1..car['helper_count']).filter_map do |n|
          person = board.member(car["helper#{n}"])
          person ? "#{person['code']} · #{person['name']}" : car["external_helper#{n}"].presence
        end.join("\n")
        maps.map do |map|
          [I18n.l(board.date), car['plate'] || 'Pendente', map['number'] || 'Pendente', TimeOff::Coverage::OPERATIONS.fetch(car['operation']),
            driver&.fetch('code', nil) || car['external_driver_code'], driver&.fetch('name', nil) || car['external_driver'].presence || 'Falta motorista',
            helpers.presence || (car['helper_count'].zero? ? 'Sem ajudante' : 'Falta ajudante'), map['deliveries'], map['cities'], map['region'], map['km'], map['duration'], map['boxes'], map['box_occupancy'], map['weight'], map['weight_occupancy']].map { |v| safe(v) }
        end
      end
      widths = [47, 43, 38, 28, 25, 75, 82, 22, 82, 140, 32, 40, 35, 30, 35, 32]
      scale = bounds.width / widths.sum
      table([header.map { |v| safe(v) }, *rows], header: true, column_widths: widths.map { |w| w * scale },
        cell_style: { size: 6, padding: 4, border_color: 'C5CCD3', valign: :center }, row_colors: ['FFFFFF', 'F4F6F8']) do
        row(0).font_style = :bold
        row(0).background_color = 'E6EBF0'
      end
      cars.select { |c| c['notes'].present? }.each do |car|
        move_down 4
        text safe("#{car['plate'] || 'Sem placa'} · #{car['notes']}"), size: 7
      end
    end
    if groups.empty?
      text safe("PCD SALAS · #{I18n.l(board.date)}"), size: 16, style: :bold
      move_down 12
      text safe('Nenhuma saída prevista.'), size: 10
    end
    number_pages safe('PCD SALAS · <page>/<total>'), at: [bounds.right - 125, 0], width: 125, size: 7, align: :right
  end

  private

  def safe(value)
    value.to_s
  end
end
