module FuelConsumptionsHelper
  def fuel_metric(value, precision: 2)
    value.nil? ? '—' : number_with_precision(value, precision: precision, separator: ',', delimiter: '.')
  end

  def fuel_goal_status(totals)
    return 'Sem meta comparável' if totals[:goal].nil?
    totals[:achieved] ? 'Meta atingida' : 'Abaixo da meta'
  end

  def fuel_label(value)
    { 'dieselS10' => 'Diesel S10', 'dieselS10Aditivado' => 'Diesel S10 aditivado',
      'dieselS500' => 'Diesel S500', 'gasolina' => 'Gasolina', 'gasolinaAditivada' => 'Gasolina aditivada',
      'etanol' => 'Etanol', 'etanolAditivado' => 'Etanol aditivado', 'gas' => 'Gás' }.fetch(value, value)
  end
end
