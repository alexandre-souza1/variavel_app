
module FleetAvailabilities
  class Creator
    def self.call(...)
      new(...).call
    end

    def initialize(
      user:,
      date:,
      agreed_quantity:,
      special_routes: [],
      copy_from: nil,
      copy_previous_day: false
    )
      @user = user
      @date = date.to_date
      @agreed_quantity = agreed_quantity.to_i
      @special_routes = special_routes
      @copy_from = copy_from
      @copy_previous_day = copy_previous_day
    end

    def call
      ActiveRecord::Base.transaction do
        availability = create_availability

        if @copy_from.present?
          copy_all_items(availability, @copy_from)
        elsif @copy_previous_day
          previous = previous_day_availability
          if previous
            copy_all_items(availability, previous)
          else
            create_default_items(availability)
          end
        else
          previous = previous_day_availability
          if previous
            create_items_with_unavailable_from_previous(availability, previous)
          else
            create_default_items(availability)
          end
        end

        availability
      end
    end

    private

    def create_availability
      FleetAvailability.create!(
        user: @user,
        date: @date,
        agreed_quantity: @agreed_quantity,
        special_routes: @special_routes
      )
    end

    # Cria todos os itens com as chaves padronizadas
    def base_item_attributes(availability_id)
      {
        fleet_availability_id: availability_id,
        reason: nil,
        observation: nil,
        special_route: nil,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # Cria itens padrão: primeiros N como "available", resto como "exchange"
    def create_default_items(availability)
      base = base_item_attributes(availability.id)

      items = Plate.where(setor: "ROTA")
                   .ordered
                   .each_with_index.map do |plate, index|
        status = index < availability.agreed_quantity.to_i ?
                   FleetAvailabilityItem.statuses[:available] :
                   FleetAvailabilityItem.statuses[:exchange]

        base.merge(
          plate_id: plate.id,
          status: status,
          position: index
        )
      end

      FleetAvailabilityItem.insert_all!(items) if items.any?
    end

    # Copia todos os itens de uma disponibilidade fonte
    def copy_all_items(availability, source)
      items = source.fleet_availability_items
                    .includes(:plate)
                    .map do |item|
        {
          fleet_availability_id: availability.id,
          plate_id: item.plate_id,
          status: FleetAvailabilityItem.statuses[item.status],
          position: item.position,
          reason: item.reason,
          observation: item.observation,
          special_route: item.special_route,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      FleetAvailabilityItem.insert_all!(items) if items.any?
    end

    # Cria itens mesclando:
    # - Copia os itens com status "unavailable" do dia anterior (mantendo posição, observações, reason, special_route)
    # - Para as demais posições, preenche com "available" ou "exchange" conforme a quantidade acordada
    def create_items_with_unavailable_from_previous(availability, previous)
      base = base_item_attributes(availability.id)
      total_positions = availability.agreed_quantity.to_i
      all_plates = Plate.where(setor: "ROTA").ordered.to_a

      # 1. Mapeia os itens unavailable do dia anterior
      unavailable_items = previous.fleet_availability_items
                                  .where(status: FleetAvailabilityItem.statuses[:unavailable])
                                  .order(:position)

      unavailable_by_position = {}
      extra_unavailable = []

      unavailable_items.each do |item|
        data = {
          plate_id: item.plate_id,
          status: FleetAvailabilityItem.statuses[:unavailable],
          position: item.position,
          reason: item.reason,
          observation: item.observation,
          special_route: item.special_route
        }

        if item.position < total_positions
          unavailable_by_position[item.position] = data
        else
          extra_unavailable << data.dup
        end
      end

      # 2. Construir a lista final de itens
      items = []
      occupied_positions = Set.new

      # Adiciona os unavailable que cabem nas posições
      unavailable_by_position.each do |pos, data|
        items << base.merge(
          plate_id: data[:plate_id],
          status: data[:status],
          position: pos,
          reason: data[:reason],
          observation: data[:observation],
          special_route: data[:special_route]
        )
        occupied_positions.add(pos)
      end

      # 3. Preencher posições vazias com available (usando placas não utilizadas)
      used_plate_ids = items.map { |i| i[:plate_id] }.compact
      available_plates = all_plates.reject { |p| used_plate_ids.include?(p.id) }

      position_index = 0
      available_plates.each do |plate|
        position_index += 1 while occupied_positions.include?(position_index)
        break if position_index >= total_positions

        items << base.merge(
          plate_id: plate.id,
          status: FleetAvailabilityItem.statuses[:available],
          position: position_index
        )
        occupied_positions.add(position_index)
        position_index += 1
      end

      # 4. Adicionar os extra_unavailable (que estavam além do total) como unavailable realocados
      extra_unavailable.each_with_index do |data, idx|
        pos = total_positions + idx
        items << base.merge(
          plate_id: data[:plate_id],
          status: FleetAvailabilityItem.statuses[:unavailable],
          position: pos,
          reason: data[:reason],
          observation: data[:observation],
          special_route: data[:special_route]
        )
      end

      # 5. Placas restantes viram exchange
      used_plate_ids_after = items.map { |i| i[:plate_id] }.compact
      remaining_plates = all_plates.reject { |p| used_plate_ids_after.include?(p.id) }

      remaining_plates.each_with_index do |plate, idx|
        pos = total_positions + extra_unavailable.size + idx
        items << base.merge(
          plate_id: plate.id,
          status: FleetAvailabilityItem.statuses[:exchange],
          position: pos
        )
      end

      FleetAvailabilityItem.insert_all!(items) if items.any?
    end

    def previous_day_availability
      FleetAvailability
        .where("date < ?", @date)
        .order(date: :desc)
        .first
    end
  end
end
