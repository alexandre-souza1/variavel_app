module InvoicesHelper
  # Trunca uma lista de atributos de objetos com "..." se passar do limite
  def truncated_list(collection, attribute, limit = 3)
    return "" if collection.blank?

    values = collection.map(&attribute)
    display_values = values.first(limit)
    result = display_values.join(", ")
    result += "…" if values.size > limit
    result
  end
end
