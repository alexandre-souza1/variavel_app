module FleetAvailabilitiesHelper
  def fleet_missing_tires_message(plate, summary)
    return if plate.setor == "ARMAZEM"

    expected = plate.tire_layout&.sum { |axle| axle[:tires] }
    return unless expected&.positive?

    actual = summary&.dig(:operational_count).to_i
    return if actual >= expected

    "Pneus faltantes no Prolog: #{actual} de #{expected} pneus em uso cadastrados. Corrija o cadastro no Prolog."
  end

  def tread_depth_badge_class(depth)
    case depth.to_f
    when 5.0..Float::INFINITY
      "fleet-tread-depth-badge--good"
    when 3.0...5.0
      "fleet-tread-depth-badge--attention"
    else
      "fleet-tread-depth-badge--critical"
    end
  end
end
