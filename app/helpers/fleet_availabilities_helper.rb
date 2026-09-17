module FleetAvailabilitiesHelper
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
