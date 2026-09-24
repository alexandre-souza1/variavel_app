module TireInspectionsHelper
  def pressure_status_label(status)
    { "persisted" => "Permaneceu baixa", "normalized" => "Normalizou", "pending" => "Última leitura baixa no período", "current_low" => "Incorreto · pressão baixa no mês atual", "awaiting_month" => "Pressão baixa · sem aferição no mês atual", "unknown" => "Sem comparação válida" }.fetch(status)
  end
end
