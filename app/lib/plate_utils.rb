module PlateUtils
  MERCOSUL = {
    "0" => "A",
    "1" => "B",
    "2" => "C",
    "3" => "D",
    "4" => "E",
    "5" => "F",
    "6" => "G",
    "7" => "H",
    "8" => "I",
    "9" => "J"
  }.freeze

  ANTIGA = MERCOSUL.invert.freeze

  module_function

  def normalizar(placa)
    placa.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end

  def equivalentes(placa)
    placa = normalizar(placa)

    return [] unless placa.length == 7

    placas = [placa]

    # Antiga -> Mercosul
    if placa[3] =~ /\d/ && placa[4] =~ /\d/
      mercosul = placa.dup
      mercosul[4] = MERCOSUL[placa[4]]
      placas << mercosul
    end

    # Mercosul -> Antiga
    if placa[3] =~ /\d/ && placa[4] =~ /[A-J]/
      antiga = placa.dup
      antiga[4] = ANTIGA[placa[4]]
      placas << antiga
    end

    placas.uniq
  end
end
