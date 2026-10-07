module MechanicTasksHelper
  def mechanic_task_return_fields
    safe_join(@filter_params.flat_map do |key, value|
      if value.is_a?(Array)
        value.map { |item| hidden_field_tag "mechanic_filters[#{key}][]", item, id: nil }
      else
        hidden_field_tag "mechanic_filters[#{key}]", value, id: nil
      end
    end)
  end

  def mechanic_label_color(label)
    label.color.to_s.match?(/\A#(?:[0-9a-f]{3}|[0-9a-f]{6})\z/i) ? label.color : "#6b7280"
  end
end
