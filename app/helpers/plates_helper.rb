module PlatesHelper
  def tire_low_tread?(tire)
    depth = tire&.dig(:smallest_tread_depth)
    !depth.nil? && depth < 3.5
  end

  def tire_tread_tooltip(tire)
    depth = tire&.dig(:smallest_tread_depth)
    return "Menor sulco: sem medição" if depth.nil?

    "Menor sulco: #{number_with_precision(depth, precision: 2, strip_insignificant_zeros: true)} mm"
  end
end
