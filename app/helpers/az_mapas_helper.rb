module AzMapasHelper
  def turno_label(numero)
    case numero
    when 0 then "A"
    when 1 then "B"
    when 2 then "C"
    else "Desconhecido"
    end
  end
end
