module OperatorsHelper
  def turno_map
    { "A" => 0, "B" => 1, "C" => 2 }
  end

  def turno_label(turno_num)
    turno_map.invert[turno_num]
  end

end
