module AzAjudantesHelper
  def turno_map
    { "A" => 0, "B" => 1, "C" => 2 }
  end

  def turno_label(turno)
    return "Não informado" if turno.blank?

    turno_map.invert[turno.to_i] || "Não informado"
  end
end
